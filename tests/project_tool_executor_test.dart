import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
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
