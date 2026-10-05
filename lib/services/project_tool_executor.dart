import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'project_attachment_loader.dart';

class ProjectToolExecutor {
  ProjectToolExecutor();

  static const supportedTools = <String>{
    'list_project_files',
    'search_project_files',
    'read_project_file',
    'edit_project_file',
    'run_command',
  };

  static const maxEditTextBytes = 16 * 1024;
  static const maxCommandTextBytes = 8 * 1024;
  static const maxCommandOutputBytes = 16 * 1024;
  static const commandTimeout = Duration(seconds: 60);

  final Map<String, String> _observedFiles = {};

  bool supports(String toolName, {bool fullAccess = false}) =>
      supportedTools.contains(toolName) &&
      (fullAccess || toolName != 'run_command');

  static const maxListedEntries = 160;
  static const maxScannedFiles = 240;
  static const maxSearchMatches = 30;
  static const maxOutputCharacters = 12000;

  static const _blockedExtensions = <String>{'jks', 'key', 'p12', 'pem', 'pfx'};
  static final _sensitiveNamePattern = RegExp(
    r'(^|[._-])(secrets?|credentials?|passwords?|passwd|tokens?)([._-]|$)',
  );

  Future<String> execute({
    required String projectPath,
    required AgentToolCall call,
    bool fullAccess = false,
    bool allowComputerPaths = false,
    Future<void>? abortTrigger,
  }) async {
    if (!call.hasValidArguments) {
      return 'Tool error: the arguments were not valid JSON. Retry with valid arguments.';
    }

    try {
      final root = await Directory(projectPath).resolveSymbolicLinks();
      return switch (call.name) {
        'list_project_files' => await _listFiles(
            root,
            call.arguments,
            allowComputerPaths: allowComputerPaths,
          ),
        'search_project_files' => await _searchFiles(
            root,
            call.arguments,
            allowComputerPaths: allowComputerPaths,
          ),
        'read_project_file' => await _readFile(
            root,
            call.arguments,
            fullAccess: fullAccess,
            allowComputerPaths: allowComputerPaths,
          ),
        'edit_project_file' => await _editFile(
            root,
            call.arguments,
            fullAccess: fullAccess,
            allowComputerPaths: allowComputerPaths,
          ),
        'run_command' when fullAccess => await _runCommand(
            root,
            call.arguments,
            abortTrigger: abortTrigger ?? Completer<void>().future,
          ),
        'run_command' =>
          'Tool error: command execution requires Full access mode.',
        _ => 'Tool error: unsupported project tool ${call.name}.',
      };
    } on ProjectAttachmentException catch (error) {
      return 'Tool error: project file action failed. ${error.message}';
    } on FileSystemException {
      return 'Tool error: the selected project folder or requested path is no longer available.';
    } on ProcessException {
      return 'Tool error: the command could not be started.';
    } catch (_) {
      return 'Tool error: the project tool could not complete this request.';
    }
  }

  Future<String> _listFiles(String root, Map<String, dynamic> arguments,
      {required bool allowComputerPaths}) async {
    final path = await _resolveToolPath(
      root,
      _optionalPath(arguments),
      allowComputerPaths: allowComputerPaths,
    );
    final directory = Directory(path.absolutePath);
    if (!await directory.exists())
      return 'Tool error: the requested computer folder was not found.';
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
    if (entries.isEmpty) return 'No readable files were found in this folder.';
    final suffix =
        hasMore ? '\nShowing the first $maxListedEntries entries.' : '';
    return _bounded(
        'Computer files in ${_displayPath(path.relativePath)}:\n${entries.join('\n')}$suffix');
  }

  Future<String> _searchFiles(String root, Map<String, dynamic> arguments,
      {required bool allowComputerPaths}) async {
    final queryValue = arguments['query'];
    if (queryValue is! String || queryValue.trim().isEmpty) {
      return 'Tool error: a non-empty search query is required.';
    }
    final query = queryValue.trim();
    if (query.length > 200)
      return 'Tool error: search queries must be 200 characters or fewer.';
    final basePath = await _resolveToolPath(
      root,
      _optionalPath(arguments),
      allowComputerPaths: allowComputerPaths,
    );
    final baseDirectory = Directory(basePath.absolutePath);
    if (!await baseDirectory.exists())
      return 'Tool error: the requested computer folder was not found.';

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
        final content = await _readSearchableFile(entity.path, relativePath);
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
      return 'No matches for ${jsonEncode(query)} were found in $scanned files.';
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
    Map<String, dynamic> arguments, {
    required bool fullAccess,
    required bool allowComputerPaths,
  }) async {
    final value = arguments['path'];
    if (value is! String || value.trim().isEmpty) {
      return 'Tool error: an absolute computer path or project-relative file path is required.';
    }
    final requested = fullAccess
        ? await _resolveFullAccessFile(root, value)
        : await _resolveToolPath(
            root,
            value,
            allowComputerPaths: allowComputerPaths,
          );
    if (!fullAccess && !_hasSupportedExtension(requested.relativePath)) {
      return 'Tool error: that file type is not available to project read tools.';
    }
    final String content;
    if (fullAccess) {
      content = await _readFullAccessTextFile(requested.absolutePath);
    } else {
      content = await _readSafeTextFile(
        requested.absolutePath,
        requested.relativePath,
      );
    }
    _observedFiles[_normalize(requested.absolutePath)] = content;
    return _bounded('File: ${requested.relativePath}\n\n$content');
  }

  Future<String> _editFile(
    String root,
    Map<String, dynamic> arguments, {
    required bool fullAccess,
    required bool allowComputerPaths,
  }) async {
    final pathValue = arguments['file_path'];
    final oldString = arguments['old_string'];
    final newString = arguments['new_string'];
    if (pathValue is! String || pathValue.trim().isEmpty) {
      throw const ProjectAttachmentException(
        'An absolute computer path or project-relative file path is required.',
      );
    }
    if (oldString is! String || oldString.isEmpty) {
      throw const ProjectAttachmentException(
        'The old text must be a non-empty string.',
      );
    }
    if (newString is! String || newString == oldString) {
      throw const ProjectAttachmentException(
        'The replacement text must be a string different from the old text.',
      );
    }
    if (utf8.encode(oldString).length > maxEditTextBytes ||
        utf8.encode(newString).length > maxEditTextBytes) {
      throw const ProjectAttachmentException(
        'A single edit cannot replace more than 16 KiB of text.',
      );
    }

    final requested = fullAccess
        ? await _resolveFullAccessFile(root, pathValue)
        : await _resolveToolPath(
            root,
            pathValue,
            allowComputerPaths: allowComputerPaths,
          );
    if (!fullAccess &&
        (!_isAllowedPath(requested.relativePath, isDirectory: false) ||
            !_hasSupportedExtension(requested.relativePath))) {
      throw const ProjectAttachmentException(
        'That file is not available to project edit tools.',
      );
    }
    final observationKey = _normalize(requested.absolutePath);
    final observedContent = _observedFiles[observationKey];
    if (observedContent == null) {
      throw const ProjectAttachmentException(
        'Read the file with read_project_file before editing it.',
      );
    }

    final currentContent = fullAccess
        ? await _readFullAccessTextFile(requested.absolutePath)
        : await _readSafeTextFile(
            requested.absolutePath,
            requested.relativePath,
          );
    if (currentContent != observedContent) {
      throw const ProjectAttachmentException(
        'The file changed after it was read. Read it again before editing.',
      );
    }

    final match = currentContent.indexOf(oldString);
    if (match < 0) {
      throw const ProjectAttachmentException(
        'The old text was not found. Read the latest file and prepare a new edit.',
      );
    }
    if (currentContent.indexOf(oldString, match + 1) >= 0) {
      throw const ProjectAttachmentException(
        'The old text appears more than once. Use a more specific unique match.',
      );
    }

    final updatedContent = currentContent.replaceRange(
      match,
      match + oldString.length,
      newString,
    );
    if (utf8.encode(updatedContent).length >
        ProjectAttachmentLoader.maxFileBytes) {
      throw const ProjectAttachmentException(
        'The edited file would exceed the 64 KiB project file limit.',
      );
    }

    await File(requested.absolutePath).writeAsString(
      updatedContent,
      encoding: utf8,
      flush: true,
    );
    _observedFiles.remove(observationKey);
    return 'Updated ${requested.relativePath}.';
  }

  Future<String> _readFullAccessTextFile(String path) async {
    final bytes = <int>[];
    await for (final chunk
        in File(path).openRead(0, ProjectAttachmentLoader.maxFileBytes + 1)) {
      final remaining = ProjectAttachmentLoader.maxFileBytes + 1 - bytes.length;
      bytes.addAll(chunk.take(remaining));
      if (bytes.length > ProjectAttachmentLoader.maxFileBytes) {
        throw const ProjectAttachmentException(
          'The file is larger than 64 KiB. Choose a smaller text file.',
        );
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const ProjectAttachmentException(
        'The file is not UTF-8 text and cannot be read or edited here.',
      );
    }
  }

  Future<String> _readSafeTextFile(String path, String displayPath) async {
    final bytes = <int>[];
    try {
      await for (final chunk
          in File(path).openRead(0, ProjectAttachmentLoader.maxFileBytes + 1)) {
        final remaining =
            ProjectAttachmentLoader.maxFileBytes + 1 - bytes.length;
        bytes.addAll(chunk.take(remaining));
        if (bytes.length > ProjectAttachmentLoader.maxFileBytes) {
          throw ProjectAttachmentException(
            '$displayPath is larger than 64 KiB. Choose a smaller text file.',
          );
        }
      }
    } on FileSystemException {
      throw const ProjectAttachmentException(
        'The requested file could not be read. Check its permissions and try again.',
      );
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw ProjectAttachmentException(
        '$displayPath is not UTF-8 text and cannot be read or edited here.',
      );
    }
  }

  Future<_ResolvedPath> _resolveFullAccessFile(
    String root,
    String requested,
  ) async {
    final path = _expandHomePath(requested.trim());
    final candidate = _isAbsolutePath(path) ? path : _joinPath(root, path);
    final type = await FileSystemEntity.type(candidate);
    if (type == FileSystemEntityType.notFound) {
      throw const ProjectAttachmentException(
          'The requested file was not found.');
    }
    if (type != FileSystemEntityType.file) {
      throw const ProjectAttachmentException(
          'The requested path is not a file.');
    }
    final resolved = await File(candidate).resolveSymbolicLinks();
    return _ResolvedPath(
      relativePath: _displayFullAccessPath(root, resolved),
      absolutePath: resolved,
    );
  }

  Future<String> _runCommand(
    String projectRoot,
    Map<String, dynamic> arguments, {
    required Future<void> abortTrigger,
  }) async {
    final command = arguments['command'];
    if (command is! String || command.trim().isEmpty) {
      throw const ProjectAttachmentException(
        'A non-empty shell command is required.',
      );
    }
    if (utf8.encode(command).length > maxCommandTextBytes) {
      throw const ProjectAttachmentException(
        'Commands cannot exceed 8 KiB.',
      );
    }
    final requestedDirectory = arguments['working_directory'];
    if (requestedDirectory != null && requestedDirectory is! String) {
      throw const ProjectAttachmentException(
        'The working directory must be a path string.',
      );
    }
    final workingDirectory = await _resolveWorkingDirectory(
      projectRoot,
      requestedDirectory is String && requestedDirectory.trim().isNotEmpty
          ? requestedDirectory.trim()
          : projectRoot,
    );

    final Process process;
    try {
      process = await Process.start(
        Platform.isWindows ? 'powershell.exe' : '/bin/sh',
        Platform.isWindows
            ? ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', command]
            : ['-lc', command],
        workingDirectory: workingDirectory,
      );
    } on ProcessException {
      return 'Tool error: the command shell could not be started.';
    }

    final stdout = StringBuffer();
    final stderr = StringBuffer();
    var outputBytes = 0;
    var truncated = false;
    void appendOutput(StringBuffer destination, String text) {
      final encoded = utf8.encode(text);
      final remaining = maxCommandOutputBytes - outputBytes;
      if (remaining <= 0) {
        truncated = true;
        return;
      }
      final included = encoded.length <= remaining
          ? encoded
          : encoded.take(remaining).toList(growable: false);
      destination.write(utf8.decode(included, allowMalformed: true));
      outputBytes += included.length;
      if (included.length != encoded.length) truncated = true;
    }

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final stdoutSubscription = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((text) => appendOutput(stdout, text),
            onDone: stdoutDone.complete);
    final stderrSubscription = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((text) => appendOutput(stderr, text),
            onDone: stderrDone.complete);

    final timeout = Completer<_CommandStop>();
    final timer = Timer(
      commandTimeout,
      () => timeout.complete(_CommandStop.timedOut),
    );
    final Object outcome;
    try {
      outcome = await Future.any<Object>([
        process.exitCode,
        abortTrigger.then((_) => _CommandStop.cancelled),
        timeout.future,
      ]);
    } finally {
      timer.cancel();
    }

    final int exitCode;
    if (outcome is _CommandStop) {
      process.kill();
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    } else {
      exitCode = outcome as int;
    }
    try {
      await Future.wait([stdoutDone.future, stderrDone.future]).timeout(
        const Duration(seconds: 2),
      );
    } on TimeoutException {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }

    final result = StringBuffer()
      ..writeln('Working directory: $workingDirectory')
      ..writeln('Exit code: $exitCode');
    if (stdout.isNotEmpty)
      result
        ..writeln('stdout:')
        ..write(stdout);
    if (stderr.isNotEmpty)
      result
        ..writeln('stderr:')
        ..write(stderr);
    if (truncated) result.write('\n[Command output truncated at 16 KiB.]');
    final output = result.toString();
    return switch (outcome) {
      _CommandStop.cancelled =>
        'Tool cancelled: command stopped by the user.\n$output',
      _CommandStop.timedOut =>
        'Tool error: command timed out after 60 seconds.\n$output',
      int code when code != 0 =>
        'Tool error: command exited with code $code.\n$output',
      _ => 'Command completed successfully.\n$output',
    };
  }

  Future<String> _resolveWorkingDirectory(
    String projectRoot,
    String requested,
  ) async {
    final path = _expandHomePath(requested);
    final candidate =
        _isAbsolutePath(path) ? path : _joinPath(projectRoot, path);
    final type = await FileSystemEntity.type(candidate);
    if (type == FileSystemEntityType.notFound) {
      throw const ProjectAttachmentException(
        'The command working directory does not exist.',
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw const ProjectAttachmentException(
        'The command working directory must be a folder.',
      );
    }
    return Directory(candidate).resolveSymbolicLinks();
  }

  String _expandHomePath(String path) {
    if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
      final home = Platform.isWindows
          ? Platform.environment['USERPROFILE']
          : Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return path == '~' ? home : _joinPath(home, path.substring(2));
      }
    }
    return path;
  }

  bool _isAbsolutePath(String path) => Platform.isWindows
      ? RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith(r'\\')
      : path.startsWith('/');

  String _joinPath(String directory, String path) {
    final normalized =
        path.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
    final base = directory.endsWith(Platform.pathSeparator)
        ? directory
        : '$directory${Platform.pathSeparator}';
    return '$base$normalized';
  }

  String _displayFullAccessPath(String root, String absolutePath) {
    final normalizedRoot = _normalize(root);
    final normalizedPath = _normalize(absolutePath);
    final prefix =
        normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
    if (normalizedPath == normalizedRoot) return '.';
    if (normalizedPath.startsWith(prefix)) {
      return absolutePath.substring(prefix.length);
    }
    return absolutePath;
  }

  Future<String?> _readSearchableFile(
    String absolutePath,
    String relativePath,
  ) async {
    try {
      return await _readSafeTextFile(absolutePath, relativePath);
    } on ProjectAttachmentException {
      return null;
    }
  }

  Future<_ResolvedPath> _resolveToolPath(
    String root,
    String requested, {
    required bool allowComputerPaths,
  }) async {
    final expanded = _expandHomePath(requested.trim());
    if (allowComputerPaths && _isAbsolutePath(expanded)) {
      return _resolveComputerPath(root, expanded);
    }
    return _resolveProjectPath(root, expanded);
  }

  Future<_ResolvedPath> _resolveComputerPath(
      String projectRoot, String path) async {
    final normalized = path.replaceAll(r'\', '/');
    late final String pathRoot;
    late final String remainder;
    late final List<String> rootSegments;
    if (Platform.isWindows) {
      final drive = RegExp(r'^([a-zA-Z]:)/').firstMatch(normalized);
      if (drive != null) {
        pathRoot = '${drive.group(1)}${Platform.pathSeparator}';
        remainder = normalized.substring(drive.end);
        rootSegments = const [];
      } else if (normalized.startsWith('//')) {
        final parts = normalized.substring(2).split('/');
        if (parts.length < 2 ||
            parts[0].isEmpty ||
            parts[1].isEmpty ||
            parts[0] == '.' ||
            parts[0] == '?' ||
            parts[1].contains(':')) {
          throw const ProjectAttachmentException(
            'Use a complete computer path with a drive or shared folder.',
          );
        }
        pathRoot =
            '${Platform.pathSeparator}${Platform.pathSeparator}${parts[0]}${Platform.pathSeparator}${parts[1]}${Platform.pathSeparator}';
        remainder = parts.skip(2).join('/');
        rootSegments = parts.take(2).toList(growable: false);
      } else {
        throw const ProjectAttachmentException(
          'Use an absolute path to access another computer folder.',
        );
      }
    } else {
      if (!normalized.startsWith('/')) {
        throw const ProjectAttachmentException(
          'Use an absolute path to access another computer folder.',
        );
      }
      pathRoot = '/';
      remainder = normalized.substring(1);
      rootSegments = const [];
    }

    final segments = remainder.split('/')
      ..removeWhere((segment) => segment.isEmpty || segment == '.');
    if (segments.any((segment) => segment == '..' || segment.contains(':'))) {
      throw const ProjectAttachmentException(
        'The requested path cannot contain parent-directory traversal.',
      );
    }
    final displayPath = [...rootSegments, ...segments].join('/');
    if (!_isAllowedPath(displayPath, isDirectory: true)) {
      throw const ProjectAttachmentException(
        'That computer path is restricted.',
      );
    }

    var candidate = pathRoot;
    for (final segment in segments) {
      candidate = _joinPath(candidate, segment);
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const ProjectAttachmentException(
          'Symbolic links are not available to file tools.',
        );
      }
      if (type == FileSystemEntityType.notFound) {
        throw const ProjectAttachmentException(
          'The requested computer file or folder does not exist.',
        );
      }
    }
    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw const ProjectAttachmentException(
        'The requested computer path is not a file or folder.',
      );
    }
    final resolved = type == FileSystemEntityType.file
        ? await File(candidate).resolveSymbolicLinks()
        : await Directory(candidate).resolveSymbolicLinks();
    return _ResolvedPath(
      relativePath:
          _displayFullAccessPath(projectRoot, resolved).replaceAll(r'\', '/'),
      absolutePath: resolved,
    );
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
          'Symbolic links are not available to project tools.',
        );
      }
    }
    final entityType = await FileSystemEntity.type(path, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) {
      throw const ProjectAttachmentException(
        'The requested file or folder does not exist in the selected project.',
      );
    }
    final resolved = entityType == FileSystemEntityType.file
        ? await File(path).resolveSymbolicLinks()
        : await Directory(path).resolveSymbolicLinks();
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
    final segments = path
        .replaceAll(r'\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty);
    for (final segment in segments) {
      final name = segment.toLowerCase();
      if (name.startsWith('.env') ||
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

enum _CommandStop { cancelled, timedOut }
