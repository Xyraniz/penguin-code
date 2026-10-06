import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/agent_hook_runner.dart';

void main() {
  group('AgentHookRunner', () {
    const runner = AgentHookRunner();

    test('a before-tool hook can block without granting approval', () async {
      final directory = await Directory.systemTemp.createTemp('penguin-hook-');
      addTearDown(() => directory.delete(recursive: true));
      final hook = _hook(
        command: Platform.isWindows
            ? "Write-Output 'Denied by local policy'; exit 2"
            : "echo 'Denied by local policy' >&2; exit 2",
      );

      final result = await runner.run(
        hooks: [hook],
        event: AgentHookEvent.beforeTool,
        workingDirectory: directory.path,
        chatId: 'chat-1',
        toolName: 'run_command',
        toolInput: {'command': 'dangerous'},
      );

      expect(result.blocked, isTrue);
      expect(result.output, contains('Denied by local policy'));
    });

    test('tool matchers and disabled hooks prevent command execution',
        () async {
      final directory = await Directory.systemTemp.createTemp('penguin-hook-');
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}${Platform.pathSeparator}ran.txt');
      final hook = _hook(
        matcher: r'^edit_project_file$',
        command: Platform.isWindows
            ? "Set-Content '${marker.path}' ran"
            : "printf ran > '${marker.path}'",
      );

      final mismatch = await runner.run(
        hooks: [hook],
        event: AgentHookEvent.beforeTool,
        workingDirectory: directory.path,
        chatId: 'chat-1',
        toolName: 'read_project_file',
      );
      final disabled = await runner.run(
        hooks: [hook.copyWith(enabled: false)],
        event: AgentHookEvent.beforeTool,
        workingDirectory: directory.path,
        chatId: 'chat-1',
        toolName: 'edit_project_file',
      );

      expect(mismatch.blocked, isFalse);
      expect(disabled.output, isEmpty);
      expect(await marker.exists(), isFalse);
    });

    test('after-tool output is returned to the agent context', () async {
      final directory = await Directory.systemTemp.createTemp('penguin-hook-');
      addTearDown(() => directory.delete(recursive: true));
      final hook = _hook(
        event: AgentHookEvent.afterTool,
        command: Platform.isWindows
            ? "Write-Output 'Run the formatter next'"
            : "printf 'Run the formatter next'",
      );

      final result = await runner.run(
        hooks: [hook],
        event: AgentHookEvent.afterTool,
        workingDirectory: directory.path,
        chatId: 'chat-1',
        toolName: 'edit_project_file',
        toolOutput: 'Updated main.dart.',
      );

      expect(result.blocked, isFalse);
      expect(result.output, contains('Run the formatter next'));
    });

    test('a timed-out before-tool hook blocks the action', () async {
      final directory = await Directory.systemTemp.createTemp('penguin-hook-');
      addTearDown(() => directory.delete(recursive: true));
      final hook = _hook(
        timeoutSeconds: 1,
        command: Platform.isWindows ? 'Start-Sleep -Seconds 5' : 'sleep 5',
      );

      final result = await runner.run(
        hooks: [hook],
        event: AgentHookEvent.beforeTool,
        workingDirectory: directory.path,
        chatId: 'chat-1',
        toolName: 'run_command',
      );

      expect(result.blocked, isTrue);
      expect(result.output, contains('timed out'));
    });
  });
}

AgentHook _hook({
  AgentHookEvent event = AgentHookEvent.beforeTool,
  required String command,
  String matcher = '',
  int timeoutSeconds = 10,
}) =>
    AgentHook(
      id: 'hook-1',
      name: 'Test hook',
      event: event,
      command: command,
      matcher: matcher,
      enabled: true,
      timeoutSeconds: timeoutSeconds,
    );
