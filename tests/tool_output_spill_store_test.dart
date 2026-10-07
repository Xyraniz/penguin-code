import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/services/tool_output_spill_store.dart';

void main() {
  group('ToolOutputSpillStore', () {
    test('keeps short results inline', () async {
      final directory = await Directory.systemTemp.createTemp('penguin-spill-');
      addTearDown(() => directory.delete(recursive: true));

      final result = await const ToolOutputSpillStore().spillIfNeeded(
        outputDirectory: directory.path,
        toolCallId: 'call-1',
        output: 'short result',
      );

      expect(result, 'short result');
      expect(directory.listSync(), isEmpty);
    });

    test('saves full output and returns a bounded recoverable preview',
        () async {
      final directory = await Directory.systemTemp.createTemp('penguin-spill-');
      addTearDown(() => directory.delete(recursive: true));
      final output = '${'head ' * 3000}\n${'tail ' * 2000}';

      final result = await const ToolOutputSpillStore().spillIfNeeded(
        outputDirectory: directory.path,
        toolCallId: 'provider-call/unsafe',
        output: output,
      );

      final artifact = File.fromUri(
        Uri.file(RegExp(r'Full tool output saved to: (.+)\n')
            .firstMatch(result)!
            .group(1)!),
      );
      expect(await artifact.readAsString(), output);
      expect(result, contains('Omitted'));
      expect(result, contains('Use read_tool_output'));
      expect(result.length, lessThan(output.length));
    });

    test('reads saved output in UTF-8 safe byte pages', () async {
      final directory = await Directory.systemTemp.createTemp('penguin-spill-');
      addTearDown(() => directory.delete(recursive: true));
      final output = '${'a' * 8191}🐧${'tail ' * 1000}';
      const store = ToolOutputSpillStore();
      final result = await store.spillIfNeeded(
        outputDirectory: directory.path,
        toolCallId: 'call-utf8',
        output: output,
      );
      final fileName =
          RegExp(r'file_name "([^"]+)"').firstMatch(result)!.group(1)!;

      final firstPage = await store.readPage(
        outputDirectory: directory.path,
        fileName: fileName,
        offset: 0,
        length: ToolOutputSpillStore.maxReadBytes,
      );
      expect(firstPage, contains('Bytes 0–8191'));
      expect(firstPage, contains('Continue with offset 8191'));
      expect(firstPage, isNot(contains('🐧')));

      final secondPage = await store.readPage(
        outputDirectory: directory.path,
        fileName: fileName,
        offset: 8191,
        length: ToolOutputSpillStore.maxReadBytes,
      );
      expect(secondPage, contains('🐧'));
      expect(secondPage, contains('tail '));
    });

    test('rejects paths that are not saved tool-output filenames', () async {
      final directory = await Directory.systemTemp.createTemp('penguin-spill-');
      addTearDown(() => directory.delete(recursive: true));

      final result = await const ToolOutputSpillStore().readPage(
        outputDirectory: directory.path,
        fileName: '../private.txt',
        offset: 0,
        length: 128,
      );

      expect(result, contains('Tool error'));
      expect(result, isNot(contains('private')));
    });
  });
}
