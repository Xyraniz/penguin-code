import 'dart:convert';
import 'dart:io';

import '../models.dart';

class ProjectAttachmentException implements Exception {
  const ProjectAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProjectAttachmentLoader {
  const ProjectAttachmentLoader();

  static const maxAttachments = 4;
  static const maxFileBytes = 64 * 1024;
  static const maxTotalBytes = 128 * 1024;

  static const supportedExtensions = [
    'c',
    'cc',
    'cpp',
    'cs',
    'css',
    'dart',
    'go',
    'h',
    'hpp',
    'html',
    'java',
    'js',
    'jsx',
    'json',
    'kt',
    'md',
    'php',
    'py',
    'rb',
    'rs',
    'sh',
    'sql',
    'swift',
    'toml',
    'ts',
    'tsx',
    'txt',
    'xml',
    'yaml',
    'yml',
  ];

  static const _supportedExtensionSet = <String>{
    ...supportedExtensions,
  };
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
  static const _blockedExtensions = <String>{
    'jks',
    'key',
    'p12',
    'p7b',
    'pfx',
    'pem',
  };
  static final _sensitiveNamePattern = RegExp(
    r'(^|[._-])(secrets?|credentials?|passwords?|passwd|tokens?)([._-]|$)',
  );

  Future<List<ChatAttachment>> readFiles({
    String? projectPath,
    required List<String> selectedPaths,
    List<ChatAttachment> alreadyAttached = const [],
  }) async {
    if (selectedPaths.isEmpty) return const [];
    if (alreadyAttached.length >= maxAttachments) {
      throw const ProjectAttachmentException(
        'A message can include up to 4 files.',
      );
    }

    final String root;
    if (projectPath == null || projectPath.isEmpty) {
      root = '';
    } else {
      final projectDirectory = Directory(projectPath);
      if (!await projectDirectory.exists()) {
        throw const ProjectAttachmentException(
          'The selected project folder is no longer available.',
        );
      }
      try {
        root = await projectDirectory.resolveSymbolicLinks();
      } on FileSystemException {
        throw const ProjectAttachmentException(
          'Could not access the selected project folder.',
        );
      }
    }
    final existingPaths = alreadyAttached
        .map((attachment) => _normalize(attachment.relativePath))
        .toSet();
    final existingBytes = alreadyAttached.fold<int>(
      0,
      (sum, attachment) => sum + attachment.sizeBytes,
    );
    var totalBytes = existingBytes;
    final loaded = <ChatAttachment>[];
    for (final selectedPath in selectedPaths) {
      _requireAbsolutePath(selectedPath);
      final file = File(selectedPath);
      final resolvedPath = await _resolveFilePath(file);
      final relativePath = root.isEmpty
          ? _standalonePath(resolvedPath)
          : _relativePath(root, resolvedPath);
      final normalizedRelativePath = _normalize(relativePath);
      if (existingPaths.contains(normalizedRelativePath) ||
          loaded.any(
            (attachment) =>
                _normalize(attachment.relativePath) == normalizedRelativePath,
          )) {
        continue;
      }
      if (alreadyAttached.length + loaded.length >= maxAttachments) {
        throw const ProjectAttachmentException(
          'A message can include up to 4 files.',
        );
      }
      _validateFileType(relativePath);
      final bytes = await _readBounded(resolvedPath, relativePath);
      totalBytes += bytes.length;
      if (totalBytes > maxTotalBytes) {
        throw const ProjectAttachmentException(
          'Attachments in one message cannot exceed 128 KiB.',
        );
      }
      final String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException {
        throw ProjectAttachmentException(
          '$relativePath is not a UTF-8 text file.',
        );
      }
      loaded.add(
        ChatAttachment(
          relativePath: relativePath,
          content: content,
          sizeBytes: bytes.length,
        ),
      );
    }
    return List.unmodifiable(loaded);
  }

  Future<String> _resolveFilePath(File file) async {
    try {
      if (!await file.exists()) {
        throw const ProjectAttachmentException(
          'A selected file could not be found. Select it again and retry.',
        );
      }
      return await file.resolveSymbolicLinks();
    } on FileSystemException {
      throw const ProjectAttachmentException(
        'Could not read a selected file. Check its permissions and try again.',
      );
    }
  }

  Future<List<int>> _readBounded(String path, String relativePath) async {
    final bytes = <int>[];
    try {
      await for (final chunk in File(path).openRead(0, maxFileBytes + 1)) {
        final remaining = maxFileBytes + 1 - bytes.length;
        bytes.addAll(chunk.take(remaining));
        if (bytes.length > maxFileBytes) {
          throw ProjectAttachmentException(
            '$relativePath is larger than 64 KiB. Choose a smaller file.',
          );
        }
      }
    } on FileSystemException {
      throw ProjectAttachmentException(
        'Could not read $relativePath. Check its permissions and try again.',
      );
    }
    return bytes;
  }

  String _relativePath(String root, String resolvedPath) {
    final normalizedRoot = _normalize(root);
    final normalizedFile = _normalize(resolvedPath);
    final prefix =
        normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
    if (!normalizedFile.startsWith(prefix)) {
      throw const ProjectAttachmentException(
        'Choose files inside the selected project folder.',
      );
    }
    final relative = resolvedPath.substring(prefix.length);
    final segments = relative.split(RegExp(r'[\\/]'));
    if (segments.any(
        (segment) => _blockedDirectories.contains(segment.toLowerCase()))) {
      throw const ProjectAttachmentException(
        'Files inside generated or version-control folders cannot be attached.',
      );
    }
    return segments.join('/');
  }

  String _standalonePath(String resolvedPath) {
    final normalized = resolvedPath.replaceAll(r'\', '/');
    final segments = normalized.split('/');
    if (segments.any(
      (segment) => _blockedDirectories.contains(segment.toLowerCase()),
    )) {
      throw const ProjectAttachmentException(
        'Files inside generated or version-control folders cannot be attached.',
      );
    }
    return segments.join('/');
  }

  void _validateFileType(String relativePath) {
    final name =
        relativePath.replaceAll(r'\', '/').split('/').last.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    final extension = dotIndex < 0 ? '' : name.substring(dotIndex + 1);
    final sensitiveName = name.startsWith('.env') ||
        _sensitiveNamePattern.hasMatch(name) ||
        name.startsWith('id_rsa') ||
        name.startsWith('id_ed25519');
    if (sensitiveName || _blockedExtensions.contains(extension)) {
      throw const ProjectAttachmentException(
        'Credential and private-key files cannot be attached.',
      );
    }
    if (!_supportedExtensionSet.contains(extension)) {
      throw const ProjectAttachmentException(
        'Choose a supported source-code or text file.',
      );
    }
  }

  void _requireAbsolutePath(String path) {
    final absolute = Platform.isWindows
        ? RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)').hasMatch(path)
        : path.startsWith('/');
    if (!absolute) {
      throw const ProjectAttachmentException(
        'The file picker returned an invalid file path.',
      );
    }
  }

  String _normalize(String path) {
    var normalized = path.replaceAll(r'\', '/');
    final isWindowsRoot =
        Platform.isWindows && RegExp(r'^[a-zA-Z]:/$').hasMatch(normalized);
    if (normalized.length > 1 && normalized.endsWith('/') && !isWindowsRoot) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
