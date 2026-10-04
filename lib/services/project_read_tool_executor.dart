import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'project_attachment_loader.dart';

class ProjectReadToolExecutor {
  const ProjectReadToolExecutor();

  static const supportedTools = <String>{
    'list_project_files',
    'search_project_files',
    'read_project_file',
  };

  bool supports(String toolName) => supportedTools.contains(toolName);

  static const maxListedEntries = 160;
  static const maxScannedFiles = 240;
  static const maxSearchMatches = 30;
  static const maxOutputCharacters = 12000;

  static const _blockedDirectories = <String>{
    '.dart_tool',
    '.git',
    '.venv',
    'build',
    'coverage',
    'dist',
    'node_modules',
    'vendor',
    'venv',
  };
  static const _blockedExtensions = <String>{'jks', 'key', 'p12', 'pem', 'pfx'};
  static final _sensitiveNamePattern = RegExp(
    r'(^|[._-])(secrets?|credentials?|passwords?|passwd|tokens?)([._-]|$)',
  );

  Future<String> execute({
    required String projectPath,
    required AgentToolCall call,
  }) async {
    if (!call.hasValidArguments) {
      return 'Tool error: the arguments were not valid JSON. Retry with valid arguments.';
    }

    try {
      final root = await Directory(projectPath).resolveSymbolicLinks();
      return switch (call.name) {
        'list_project_files' => await _listFiles(root, call.arguments),
        'search_project_files' => await _searchFiles(root, call.arguments),
        'read_project_file' => await _readFile(root, call.arguments),
        _ => 'Tool error: unsupported project tool ${call.name}.',
      };
    } on ProjectAttachmentException catch (error) {
      return 'Tool error: could not read that project file. ${error.message}';
    } on FileSystemException {
      return 'Tool error: the selected project folder or requested path is no longer available.';
    } catch (_) {
      return 'Tool error: the project tool could not complete this request.';
    }
  }

  Future<String> _listFiles(
    String root,
    Map<String, dynamic> arguments,
  ) async {
    final path = await _resolveProjectPath(root, _optionalPath(arguments));
    final directory = Directory(path.absolutePath);
    if (!await directory.exists())
      return 'Tool error: the requested project folder was not found.';
    final entries = <String>[];
    var hasMore = false;
    await for (final entity in directory.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) continue;
      final isDirectory = type == FileSystemEntityType.directory;
      final relativePath =
          _joinRelative(path.relativePath, _basename(entity.path));
      if (!_isAllowedPath(relativePath, isDirectory: isDirectory)) continue;
      if (!isDirectory && !_hasSupportedExtension(relativePath)) continue;
      if (entries.length == maxListedEntries) {
        hasMore = true;
        break;
      }
      entries.add('- $relativePath${isDirectory ? '/' : ''}');
    }
    entries.sort();
    if (entries.isEmpty)
      return 'No readable project files were found in this folder.';
    final suffix =
        hasMore ? '\nShowing the first $maxListedEntries entries.' : '';
    return _bounded(
        'Project files in ${_displayPath(path.relativePath)}:\n${entries.join('\n')}$suffix');
  }

  Future<String> _searchFiles(
    String root,
    Map<String, dynamic> arguments,
  ) async {
    final queryValue = arguments['query'];
    if (queryValue is! String || queryValue.trim().isEmpty) {
      return 'Tool error: a non-empty search query is required.';
    }
    final query = queryValue.trim();
    if (query.length > 200)
      return 'Tool error: search queries must be 200 characters or fewer.';
    final basePath = await _resolveProjectPath(root, _optionalPath(arguments));
    final baseDirectory = Directory(basePath.absolutePath);
    if (!await baseDirectory.exists())
      return 'Tool error: the requested project folder was not found.';

    final pending = <_ResolvedPath>[basePath];
    final matches = <String>[];
    var scanned = 0;
    while (pending.isNotEmpty &&
        scanned < maxScannedFiles &&
        matches.length < maxSearchMatches) {
      final current = pending.removeLast();
      await for (final entity
          in Directory(current.absolutePath).list(followLinks: false)) {
        final type =
            await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.link) continue;
        final isDirectory = type == FileSystemEntityType.directory;
        final relativePath =
            _joinRelative(current.relativePath, _basename(entity.path));
        if (!_isAllowedPath(relativePath, isDirectory: isDirectory)) continue;
        if (isDirectory) {
          pending.add(
            _ResolvedPath(
              relativePath: relativePath,
              absolutePath: entity.path,
            ),
          );
          continue;
        }
        if (!_hasSupportedExtension(relativePath)) continue;
        scanned++;
        final content =
            await _readSearchableFile(root, entity.path, relativePath);
        if (content == null) continue;
        final lines = const LineSplitter().convert(content);
        for (var index = 0; index < lines.length; index++) {
          if (lines[index].toLowerCase().contains(query.toLowerCase())) {
            matches.add('- $relativePath:${index + 1}: ${lines[index].trim()}');
            if (matches.length >= maxSearchMatches) break;
          }
        }
        if (scanned >= maxScannedFiles || matches.length >= maxSearchMatches)
          break;
      }
    }

    if (matches.isEmpty) {
      return 'No matches for ${jsonEncode(query)} were found in $scanned project files.';
    }
    final limitNote =
        scanned >= maxScannedFiles || matches.length >= maxSearchMatches
            ? '\nSearch stopped at its safety limit.'
            : '';
    return _bounded(
      'Found ${matches.length} matches for ${jsonEncode(query)} in $scanned files:\n${matches.join('\n')}$limitNote',
    );
  }

  Future<String> _readFile(
    String root,
    Map<String, dynamic> arguments,
  ) async {
    final value = arguments['path'];
    if (value is! String || value.trim().isEmpty) {
      return 'Tool error: a project-relative file path is required.';
    }
    final requested = await _resolveProjectPath(root, value);
    if (!_hasSupportedExtension(requested.relativePath)) {
      return 'Tool error: that file type is not available to project read tools.';
    }
    final loaded = await const ProjectAttachmentLoader().readFiles(
      projectPath: root,
      selectedPaths: [requested.absolutePath],
    );
    if (loaded.isEmpty)
      return 'Tool error: the requested project file could not be read.';
    return _bounded(
        'File: ${loaded.single.relativePath}\n\n${loaded.single.content}');
  }

  Future<String?> _readSearchableFile(
    String root,
    String absolutePath,
    String relativePath,
  ) async {
    try {
      final loaded = await const ProjectAttachmentLoader().readFiles(
        projectPath: root,
        selectedPaths: [absolutePath],
      );
      return loaded.isEmpty ? null : loaded.single.content;
    } on ProjectAttachmentException {
      return null;
    }
  }

  Future<_ResolvedPath> _resolveProjectPath(
      String root, String requested) async {
    final normalized = requested.trim().replaceAll(r'\', '/');
    final isWindowsAbsolute = RegExp(r'^[a-zA-Z]:').hasMatch(normalized) ||
        normalized.startsWith('//');
    if (normalized.startsWith('/') || isWindowsAbsolute) {
      throw const ProjectAttachmentException(
          'Use a path relative to the selected project.');
    }
    final segments = normalized.split('/')
      ..removeWhere((segment) => segment.isEmpty || segment == '.');
    if (segments.any((segment) => segment == '..' || segment.contains(':'))) {
      throw const ProjectAttachmentException(
          'The requested path leaves the selected project.');
    }
    final relativePath = segments.join('/');
    if (relativePath.isNotEmpty &&
        !_isAllowedPath(relativePath, isDirectory: true)) {
      throw const ProjectAttachmentException(
          'That project path is restricted.');
    }
    var path = root;
    for (final segment in segments) {
      path = '$path${Platform.pathSeparator}$segment';
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const ProjectAttachmentException(
          'Symbolic links are not available to project read tools.',
        );
      }
    }
    final resolved = await Directory(path).resolveSymbolicLinks();
    final normalizedRoot = _normalize(root);
    final normalizedResolved = _normalize(resolved);
    final rootPrefix =
        normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
    if (normalizedResolved != normalizedRoot &&
        !normalizedResolved.startsWith(rootPrefix)) {
      throw const ProjectAttachmentException(
          'The requested path leaves the selected project.');
    }
    return _ResolvedPath(relativePath: relativePath, absolutePath: resolved);
  }

  String _optionalPath(Map<String, dynamic> arguments) {
    if (arguments.containsKey('path') && arguments['path'] is! String) {
      throw const ProjectAttachmentException(
        'The path argument must be a string.',
      );
    }
    final value = arguments['path'];
    return value is String && value.trim().isNotEmpty ? value : '.';
  }

  bool _isAllowedPath(String path, {required bool isDirectory}) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    for (final segment in segments) {
      final name = segment.toLowerCase();
      if (_blockedDirectories.contains(name) ||
          name.startsWith('.env') ||
          _sensitiveNamePattern.hasMatch(name) ||
          name.startsWith('id_rsa') ||
          name.startsWith('id_ed25519')) {
        return false;
      }
      if (!isDirectory && _blockedExtensions.contains(_extension(name))) {
        return false;
      }
    }
    return true;
  }

  bool _hasSupportedExtension(String path) =>
      ProjectAttachmentLoader.supportedExtensions.contains(_extension(path));

  String _extension(String path) {
    final name = path.split('/').last.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  String _joinRelative(String parent, String name) =>
      parent.isEmpty ? name : '$parent/$name';

  String _displayPath(String path) => path.isEmpty ? '.' : path;

  String _normalize(String path) {
    final value = path.replaceAll(r'\', '/');
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  String _bounded(String value) => value.length <= maxOutputCharacters
      ? value
      : '${value.substring(0, maxOutputCharacters)}\nOutput truncated at the tool limit.';
}

class _ResolvedPath {
  const _ResolvedPath({required this.relativePath, required this.absolutePath});

  final String relativePath;
  final String absolutePath;
}
