import 'dart:convert';
import 'dart:io';

/// Saves oversized tool results in the current chat's outputs folder.
class ToolOutputSpillStore {
  const ToolOutputSpillStore();

  static const maxInlineCharacters = 12000;
  static const maxStoredBytes = 8 * 1024 * 1024;
  static const maxReadBytes = 8 * 1024;
  static const _previewHeadCharacters = 4500;
  static const _previewTailCharacters = 2500;

  Future<String> spillIfNeeded({
    required String outputDirectory,
    required String toolCallId,
    required String output,
  }) async {
    if (output.length <= maxInlineCharacters) return output;

    final bytes = utf8.encode(output);
    if (bytes.length <= maxInlineCharacters) return output;

    try {
      final root = Directory(outputDirectory);
      final rootType =
          await FileSystemEntity.type(root.path, followLinks: false);
      if (rootType == FileSystemEntityType.link ||
          (rootType != FileSystemEntityType.notFound &&
              rootType != FileSystemEntityType.directory)) {
        return output;
      }
      await root.create(recursive: true);

      final capturedBytes =
          bytes.length > maxStoredBytes ? maxStoredBytes : bytes.length;
      final truncated = capturedBytes != bytes.length;
      const marker = '\n[Stored tool output reached its 8 MiB limit.]\n';
      final bodyLimit = truncated
          ? maxStoredBytes - utf8.encode(marker).length
          : maxStoredBytes;
      final storedContent = utf8.decode(
        bytes.take(bodyLimit).toList(growable: false),
        allowMalformed: true,
      );
      final contents = truncated ? '$storedContent$marker' : storedContent;
      final file = await _createOutputFile(root, toolCallId);
      try {
        await file.writeAsString(contents, encoding: utf8, flush: true);
      } on Object {
        try {
          await file.delete();
        } on Object {
          // Keep the original file error.
        }
        rethrow;
      }

      final preview = _preview(output);
      final fileName = file.uri.pathSegments.last;
      return '$preview\n\nFull tool output saved to: ${file.path}'
          '${truncated ? '\nThe tool output exceeded the 8 MiB storage limit; the saved file contains the first 8 MiB.' : ''}'
          '\nUse read_tool_output with file_name "$fileName", offset 0, and length 8192 to retrieve it.';
    } on FileSystemException {
      return 'The tool output could not be saved to chat outputs. The original result follows:\n$output';
    } on FormatException {
      return 'The tool output could not be encoded as UTF-8 for chat outputs. The original result follows:\n$output';
    }
  }

  bool supports(String toolName) => toolName == 'read_tool_output';

  Future<String> readPage({
    required String outputDirectory,
    required String fileName,
    required int offset,
    required int length,
  }) async {
    if (!_isSpillFileName(fileName) ||
        offset < 0 ||
        length < 1 ||
        length > maxReadBytes) {
      return 'Tool error: use a saved tool-output filename, a non-negative byte offset, and a length from 1 to $maxReadBytes bytes.';
    }
    try {
      final root = Directory(outputDirectory);
      if (await FileSystemEntity.type(root.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return 'Tool error: this chat has no saved tool outputs.';
      }
      final file = File(_join(root.path, fileName));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return 'Tool error: the requested saved tool output was not found.';
      }
      final totalBytes = await file.length();
      if (offset > totalBytes) {
        return 'Tool error: the byte offset is beyond the saved tool output.';
      }
      final handle = await file.open();
      late final List<int> bytes;
      try {
        await handle.setPosition(offset);
        bytes = await handle.read(length);
      } finally {
        await handle.close();
      }
      final safeLength = _completeUtf8Length(bytes);
      final content = utf8.decode(bytes.take(safeLength).toList());
      final nextOffset = offset + safeLength;
      final isComplete = nextOffset >= totalBytes;
      return 'Saved tool output $fileName ($totalBytes bytes). Bytes $offset–$nextOffset:\n$content\n\n${isComplete ? 'End of saved output.' : 'Continue with offset $nextOffset.'}';
    } on FileSystemException {
      return 'Tool error: the saved tool output could not be read.';
    } on FormatException {
      return 'Tool error: the saved tool output is not valid UTF-8 text.';
    }
  }

  Future<File> _createOutputFile(Directory root, String toolCallId) async {
    final normalizedId = toolCallId
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final id = normalizedId.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : normalizedId.substring(0, normalizedId.length.clamp(0, 48).toInt());
    for (var suffix = 0; suffix < 100; suffix++) {
      final suffixText = suffix == 0 ? '' : '-$suffix';
      final file = File(
        _join(root.path, 'tool-output-$id$suffixText.txt'),
      );
      try {
        await file.create(exclusive: true);
        return file;
      } on FileSystemException {
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          rethrow;
        }
      }
    }
    throw const FileSystemException('Could not allocate a unique output file.');
  }

  String _preview(String output) {
    final headLength = _previewHeadCharacters.clamp(0, output.length).toInt();
    final tailLength = _previewTailCharacters.clamp(0, output.length).toInt();
    final head = output.substring(0, headLength);
    final tailStart = (output.length - tailLength).clamp(0, output.length);
    final tail = output.substring(tailStart);
    final omitted = output.length - head.length - tail.length;
    return '$head\n\n[Omitted $omitted characters from this preview.]\n\n$tail';
  }

  bool _isSpillFileName(String value) =>
      value.startsWith('tool-output-') &&
      value.endsWith('.txt') &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains(':') &&
      !value.contains('..') &&
      !value.contains('\u0000');

  int _completeUtf8Length(List<int> bytes) {
    for (var length = bytes.length; length >= bytes.length - 3; length--) {
      try {
        utf8.decode(bytes.take(length).toList());
        return length;
      } on FormatException {
        // A requested range can end inside a UTF-8 code point. Return a
        // shorter page and let the next request start at that boundary.
      }
    }
    throw const FormatException('Invalid UTF-8 output.');
  }

  String _join(String directory, String filename) =>
      '$directory${Platform.pathSeparator}$filename';
}
