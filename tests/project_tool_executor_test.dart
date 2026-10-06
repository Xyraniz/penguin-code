import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/checkpoint_repository.dart';
import 'package:penguin_code/services/project_tool_executor.dart';

void main() {
  group('ProjectToolExecutor', () {
    test('edits one unique match after reading the unchanged file', () async {
      final project = await _createProject('const greeting = "Hello";\n');
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}main.dart');
      final executor = ProjectToolExecutor();

      final beforeRead = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'main.dart',
          'old_string': 'Hello',
          'new_string': 'Penguin',
        }),
      );
      expect(beforeRead, contains('Read the file'));
      expect(await source.readAsString(), contains('Hello'));

      final read = await executor.execute(
        projectPath: project.path,
        call: _call('read_project_file', {'path': 'main.dart'}),
      );
      expect(read, contains('const greeting = "Hello";'));

      final result = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'main.dart',
          'old_string': 'Hello',
          'new_string': 'Penguin',
        }),
      );

      expect(result, 'Updated main.dart.');
      expect(await source.readAsString(), 'const greeting = "Penguin";\n');

      final secondEdit = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'main.dart',
          'old_string': 'Penguin',
          'new_string': 'changed again',
        }),
      );
      expect(secondEdit, contains('Read the file'));
      expect(await source.readAsString(), 'const greeting = "Penguin";\n');
    });

    test('refuses a stale read without changing the newer file', () async {
      final project = await _createProject('const value = 1;\n');
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}main.dart');
      final executor = ProjectToolExecutor();
      await executor.execute(
        projectPath: project.path,
        call: _call('read_project_file', {'path': 'main.dart'}),
      );
      await source.writeAsString('const value = 2;\n');

      final result = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'main.dart',
          'old_string': '1',
          'new_string': '3',
        }),
      );

      expect(result, contains('file changed after it was read'));
      expect(await source.readAsString(), 'const value = 2;\n');
    });

    test('refuses an ambiguous match without changing the file', () async {
      final project = await _createProject('old value; old value;\n');
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}main.dart');
      final executor = ProjectToolExecutor();
      await executor.execute(
        projectPath: project.path,
        call: _call('read_project_file', {'path': 'main.dart'}),
      );

      final result = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'main.dart',
          'old_string': 'old value',
          'new_string': 'new value',
        }),
      );

      expect(result, contains('more than once'));
      expect(await source.readAsString(), 'old value; old value;\n');
    });

    test('rejects traversal and sensitive paths', () async {
      final project = await Directory.systemTemp.createTemp('penguin-tools-');
      final outside = await Directory.systemTemp.createTemp('penguin-outside-');
      addTearDown(() => project.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final secret =
          File('${outside.path}${Platform.pathSeparator}secret.dart');
      await secret.writeAsString('const token = "private";');
      final env = File('${project.path}${Platform.pathSeparator}.env.dart');
      await env.writeAsString('const token = "private";');
      final executor = ProjectToolExecutor();

      final traversal = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': '../${secret.uri.pathSegments.last}',
          'old_string': 'private',
          'new_string': 'changed',
        }),
      );
      final credential = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': '.env.dart',
          'old_string': 'private',
          'new_string': 'changed',
        }),
      );

      expect(traversal, contains('leaves the selected project'));
      expect(credential, contains('restricted'));
      expect(await secret.readAsString(), contains('private'));
      expect(await env.readAsString(), contains('private'));
    });

    test('full access reads and edits text files outside the project',
        () async {
      final workspace = await Directory.systemTemp.createTemp('penguin-full-');
      addTearDown(() => workspace.delete(recursive: true));
      final project = Directory(
        '${workspace.path}${Platform.pathSeparator}project',
      );
      await project.create();
      final externalFile = File(
        '${workspace.path}${Platform.pathSeparator}notes.custom',
      );
      await externalFile.writeAsString('Remember the blue sky.\n');
      final executor = ProjectToolExecutor();

      final read = await executor.execute(
        projectPath: project.path,
        fullAccess: true,
        call: _call('read_project_file', {'path': externalFile.path}),
      );
      expect(read, contains('Remember the blue sky.'));

      final edit = await executor.execute(
        projectPath: project.path,
        fullAccess: true,
        call: _call('edit_project_file', {
          'file_path': externalFile.path,
          'old_string': 'blue sky',
          'new_string': 'clear ice',
        }),
      );
      expect(edit, contains('Updated'));
      expect(await externalFile.readAsString(), 'Remember the clear ice.\n');
    });

    test('checkpoints app edits and shell command changes for recovery',
        () async {
      final dataRoot = await Directory.systemTemp.createTemp('penguin-data-');
      final project = await Directory.systemTemp.createTemp('penguin-work-');
      addTearDown(() => dataRoot.delete(recursive: true));
      addTearDown(() => project.delete(recursive: true));
      final source = File('${project.path}${Platform.pathSeparator}main.dart');
      await source.writeAsString('before\n');
      final checkpoints = CheckpointRepository(dataRoot: dataRoot);
      final executor = ProjectToolExecutor(
        checkpointRepository: checkpoints,
        chatId: 'chat-1',
      );

      await executor.execute(
        projectPath: project.path,
        call: _call('read_project_file', {'path': 'main.dart'}),
      );
      final edit = await executor.execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'main.dart',
          'old_string': 'before',
          'new_string': 'after',
        }),
      );
      expect(edit, contains('Checkpoint'));
      final editCheckpoint = (await checkpoints.list()).first;
      await checkpoints.restore(editCheckpoint.id);
      expect(await source.readAsString(), 'before\n');

      final created = File(
        '${project.path}${Platform.pathSeparator}created.txt',
      );
      final command = Platform.isWindows
          ? "Set-Content -LiteralPath '${created.path}' -Value 'created'"
          : "printf created > '${created.path}'";
      final result = await executor.execute(
        projectPath: project.path,
        fullAccess: true,
        call: _call('run_command', {
          'command': command,
          'working_directory': project.path,
        }),
      );
      expect(result, contains('Checkpoint'));
      expect((await created.readAsString()).trim(), 'created');
      final commandCheckpoint = (await checkpoints.list()).firstWhere(
        (checkpoint) => checkpoint.toolName == 'run_command',
      );
      await checkpoints.restore(commandCheckpoint.id);
      expect(await created.exists(), isFalse);
    });

    test('runs commands only in full access mode', () async {
      final project = await Directory.systemTemp.createTemp('penguin-command-');
      final externalDirectory =
          await Directory.systemTemp.createTemp('penguin-command-cwd-');
      addTearDown(() => project.delete(recursive: true));
      addTearDown(() => externalDirectory.delete(recursive: true));
      final executor = ProjectToolExecutor();
      final command = Platform.isWindows
          ? "Write-Output 'penguin-command-ok'"
          : "printf 'penguin-command-ok'";
      final call = _call('run_command', {'command': command});

      final denied = await executor.execute(
        projectPath: project.path,
        call: call,
      );
      expect(denied, contains('requires Full access mode'));

      final result = await executor.execute(
        projectPath: project.path,
        call: call,
        fullAccess: true,
      );
      expect(result, contains('Command completed successfully.'));
      expect(result, contains('Exit code: 0'));
      expect(result, contains('penguin-command-ok'));

      final printWorkingDirectory =
          Platform.isWindows ? '(Get-Location).Path' : 'pwd';
      final externalCommand = await executor.execute(
        projectPath: project.path,
        fullAccess: true,
        call: _call('run_command', {
          'command': printWorkingDirectory,
          'working_directory': externalDirectory.path,
        }),
      );
      expect(
        externalCommand.toLowerCase(),
        contains(externalDirectory.path.toLowerCase()),
      );

      final outputCommand = Platform.isWindows
          ? "Write-Output ('x' * 20000)"
          : "printf '%020000d' 0";
      final boundedOutput = await executor.execute(
        projectPath: project.path,
        fullAccess: true,
        call: _call('run_command', {'command': outputCommand}),
      );
      expect(boundedOutput, contains('Command output truncated at 16 KiB'));
      expect(
        utf8.encode(boundedOutput).length,
        lessThan(ProjectToolExecutor.maxCommandOutputBytes + 512),
      );
    });

    test('stops the active shell when generation is cancelled', () async {
      final project = await Directory.systemTemp.createTemp('penguin-stop-');
      addTearDown(() => project.delete(recursive: true));
      final stop = Completer<void>();
      final command =
          Platform.isWindows ? 'Start-Sleep -Seconds 30' : 'exec sleep 30';
      final running = ProjectToolExecutor().execute(
        projectPath: project.path,
        fullAccess: true,
        abortTrigger: stop.future,
        call: _call('run_command', {'command': command}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      stop.complete();

      final result = await running.timeout(const Duration(seconds: 6));
      expect(result, startsWith('Tool cancelled:'));
    });

    test('rejects symbolic links', () async {
      final project = await Directory.systemTemp.createTemp('penguin-tools-');
      final outside = await Directory.systemTemp.createTemp('penguin-outside-');
      addTearDown(() => project.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final target =
          File('${outside.path}${Platform.pathSeparator}target.dart');
      await target.writeAsString('const value = 1;');
      final link = Link('${project.path}${Platform.pathSeparator}link.dart');
      try {
        await link.create(target.path);
      } on FileSystemException {
        markTestSkipped(
            'The current Windows environment cannot create symlinks.');
        return;
      }

      final result = await ProjectToolExecutor().execute(
        projectPath: project.path,
        call: _call('edit_project_file', {
          'file_path': 'link.dart',
          'old_string': '1',
          'new_string': '2',
        }),
      );

      expect(result, contains('Symbolic links are not available'));
      expect(await target.readAsString(), 'const value = 1;');
    });
  });
}

Future<Directory> _createProject(String content) async {
  final project = await Directory.systemTemp.createTemp('penguin-tools-');
  await File('${project.path}${Platform.pathSeparator}main.dart')
      .writeAsString(content);
  return project;
}

AgentToolCall _call(String name, Map<String, dynamic> arguments) =>
    AgentToolCall(
      id: 'tool-call',
      name: name,
      arguments: arguments,
      rawArguments: '',
      hasValidArguments: true,
    );
