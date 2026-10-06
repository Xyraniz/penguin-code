import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/services/checkpoint_repository.dart';

void main() {
  group('CheckpointRepository', () {
    test('previews changes and restores files changed by a tool', () async {
      final dataRoot = await Directory.systemTemp.createTemp('penguin-data-');
      final project = await Directory.systemTemp.createTemp('penguin-work-');
      addTearDown(() => dataRoot.delete(recursive: true));
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}main.dart');
      final removed = File('${project.path}${Platform.pathSeparator}old.txt');
      await source.writeAsString('before\n');
      await removed.writeAsString('remove me\n');
      final repository = CheckpointRepository(dataRoot: dataRoot);

      final capture = await repository.beginDirectory(
        rootPath: project.path,
        chatId: 'chat-1',
        toolName: 'run_command',
      );
      await source.writeAsString('after\n');
      await removed.delete();
      final added = File('${project.path}${Platform.pathSeparator}new.txt');
      await added.writeAsString('created\n');
      final checkpoint = await repository.finish(capture);

      expect(checkpoint, isNotNull);
      expect(
          checkpoint!.files.map((file) => file.path),
          containsAll([
            'main.dart',
            'new.txt',
            'old.txt',
          ]));
      final preview = await repository.preview(checkpoint.id, 'main.dart');
      expect(preview.before, 'before\n');
      expect(preview.after, 'after\n');

      final restored = await repository.restore(checkpoint.id);

      expect(restored.restored, 3);
      expect(restored.keptUserChanges, 0);
      expect(await source.readAsString(), 'before\n');
      expect(await removed.readAsString(), 'remove me\n');
      expect(await added.exists(), isFalse);
      expect(restored.recoveryCheckpointId, isNotNull);
    });

    test('preserves a user edit made after the agent checkpoint', () async {
      final dataRoot = await Directory.systemTemp.createTemp('penguin-data-');
      final project = await Directory.systemTemp.createTemp('penguin-work-');
      addTearDown(() => dataRoot.delete(recursive: true));
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}main.dart');
      await source.writeAsString('original\n');
      final repository = CheckpointRepository(dataRoot: dataRoot);

      final capture = await repository.beginFile(
        filePath: source.path,
        chatId: 'chat-2',
        toolName: 'edit_project_file',
      );
      await source.writeAsString('agent change\n');
      final checkpoint = await repository.finish(capture);
      await source.writeAsString('my later edit\n');

      final restored = await repository.restore(checkpoint!.id);

      expect(restored.restored, 0);
      expect(restored.keptUserChanges, 1);
      expect(await source.readAsString(), 'my later edit\n');
    });

    test('drops no-op checkpoints and caps snapshots to one requested file',
        () async {
      final dataRoot = await Directory.systemTemp.createTemp('penguin-data-');
      final project = await Directory.systemTemp.createTemp('penguin-work-');
      addTearDown(() => dataRoot.delete(recursive: true));
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}one.txt');
      final other = File('${project.path}${Platform.pathSeparator}two.txt');
      await source.writeAsString('same');
      await other.writeAsString('untouched');
      final repository = CheckpointRepository(dataRoot: dataRoot);

      final noOp = await repository.beginFile(
        filePath: source.path,
        chatId: 'chat-3',
        toolName: 'edit_project_file',
      );
      expect(await repository.finish(noOp), isNull);
      expect(await repository.list(), isEmpty);

      final capture = await repository.beginFile(
        filePath: source.path,
        chatId: 'chat-3',
        toolName: 'edit_project_file',
      );
      await source.writeAsString('changed');
      final checkpoint = await repository.finish(capture);

      expect(checkpoint!.singleFileScope, isTrue);
      expect(checkpoint.files.map((file) => file.path), ['one.txt']);
      expect(await other.readAsString(), 'untouched');
    });
  });
}
