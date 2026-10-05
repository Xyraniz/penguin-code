import 'dart:convert';
import 'dart:io';

import '../models.dart';

class ChatOutputExecutor {
  static const maxOutputBytes = 1024 * 1024;
  static const supportedExtensions = <String>{
    'c',
    'cpp',
    'css',
    'csv',
    'dart',
    'diff',
    'go',
    'h',
    'html',
    'ini',
    'java',
    'js',
    'jsx',
    'json',
    'log',
    'md',
    'ps1',
    'py',
    'rs',
    'sh',
    'sql',
    'svg',
    'toml',
    'ts',
    'tsx',
    'txt',
    'vue',
    'xml',
    'yaml',
    'yml',
  };

  bool supports(String toolName) => toolName == 'save_chat_output';

  Future<String> execute({
    required String outputDirectory,
    required AgentToolCall call,
  }) async {
    if (!supports(call.name) || !call.hasValidArguments) {
      return 'Tool error: this output action is not available.';
    }
    try {
      final relativePath = call.arguments['file_path'];
      final contents = call.arguments['content'];
      if (relativePath is! String || contents is! String) {
        return 'Tool error: provide a relative file_path and text content.';
      }
      final segments = _validatedSegments(relativePath);
      if (segments == null) {
        return 'Tool error: use a safe relative file path inside this chat output folder.';
      }
      final filename = segments.last;
      final extension =
          filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
      if (!supportedExtensions.contains(extension) ||
          _sensitiveName.hasMatch(filename)) {
        return 'Tool error: this filename or file type is not allowed in chat outputs.';
      }
      if (utf8.encode(contents).length > maxOutputBytes) {
        return 'Tool error: chat output files are limited to 1 MiB.';
      }

      final root = Directory(outputDirectory);
      if (await FileSystemEntity.type(root.path, followLinks: false) ==
          FileSystemEntityType.link) {
        return 'Tool error: the chat output folder cannot be a symbolic link.';
      }
      await root.create(recursive: true);
      var parent = root;
      for (final segment in segments.take(segments.length - 1)) {
        parent = Directory(_join([parent.path, segment]));
        final type =
            await FileSystemEntity.type(parent.path, followLinks: false);
        if (type == FileSystemEntityType.link ||
            (type != FileSystemEntityType.notFound &&
                type != FileSystemEntityType.directory)) {
          return 'Tool error: output folders cannot contain symbolic links or files in the requested path.';
        }
        await parent.create();
      }
      final file = File(_join([parent.path, filename]));
      final existingType =
          await FileSystemEntity.type(file.path, followLinks: false);
      if (existingType == FileSystemEntityType.link) {
        return 'Tool error: chat outputs cannot overwrite symbolic links.';
      }
      if (existingType != FileSystemEntityType.notFound) {
        return 'Tool error: this output file already exists. Choose a new filename to preserve it.';
      }
      await file.create(exclusive: true);
      await file.writeAsString(contents, flush: true);
      return 'Created chat output: ${file.path}';
    } on FileSystemException catch (error) {
      return 'Tool error: could not save the chat output (${error.message}).';
    } on FormatException {
      return 'Tool error: the requested output path is invalid.';
    }
  }

  static final _sensitiveName = RegExp(
    r'(^|[._-])(secrets?|credentials?|passwords?|passwd|tokens?|private[_-]?key)([._-]|$)|^\.env',
    caseSensitive: false,
  );

  List<String>? _validatedSegments(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains(':') ||
        normalized.contains('\u0000')) {
      return null;
    }
    final segments = normalized.split('/');
    if (segments.any((segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.endsWith('.') ||
        segment.endsWith(' '))) {
      return null;
    }
    return segments;
  }

  String _join(List<String> parts) => parts.join(Platform.pathSeparator);
}
