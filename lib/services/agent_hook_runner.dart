import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';

class AgentHookResult {
  const AgentHookResult({this.blocked = false, this.output = ''});

  final bool blocked;
  final String output;
}

class AgentHookRunner {
  const AgentHookRunner();

  static const maxHooksPerEvent = 12;
  static const maxOutputBytes = 8 * 1024;
  static const maxInputBytes = 32 * 1024;

  Future<AgentHookResult> run({
    required List<AgentHook> hooks,
    required AgentHookEvent event,
    required String workingDirectory,
    required String chatId,
    String provider = '',
    String model = '',
    String toolName = '',
    Map<String, dynamic> toolInput = const {},
    String toolOutput = '',
    Future<void>? abortTrigger,
  }) async {
    final matching = hooks
        .where((hook) =>
            hook.enabled && hook.event == event && _matches(hook, toolName))
        .take(maxHooksPerEvent);
    final output = <String>[];
    for (final hook in matching) {
      final result = await _runOne(
        hook,
        workingDirectory: workingDirectory,
        payload: {
          'event': event.name,
          'session_id': chatId,
          'cwd': workingDirectory,
          'provider': provider,
          'model': model,
          if (toolName.isNotEmpty) 'tool_name': toolName,
          if (event != AgentHookEvent.agentFinished) 'tool_input': toolInput,
          if (event == AgentHookEvent.afterTool) 'tool_output': toolOutput,
        },
        abortTrigger: abortTrigger,
      );
      if (event == AgentHookEvent.beforeTool &&
          (result.exitCode == 2 || result.exitCode < 0)) {
        final reason = result.text.trim().isEmpty
            ? 'A configured before-tool hook stopped the action.'
            : result.text.trim();
        return AgentHookResult(blocked: true, output: reason);
      }
      if (result.text.trim().isNotEmpty) {
        output.add('[${hook.name}] ${result.text.trim()}');
      }
      if (result.exitCode != 0) {
        output.add('[${hook.name}] Hook exited with code ${result.exitCode}.');
      }
    }
    return AgentHookResult(output: output.join('\n'));
  }

  bool _matches(AgentHook hook, String toolName) {
    if (toolName.isEmpty || hook.matcher.isEmpty) return true;
    try {
      return RegExp(hook.matcher).hasMatch(toolName);
    } on FormatException {
      return false;
    }
  }

  Future<({int exitCode, String text})> _runOne(
    AgentHook hook, {
    required String workingDirectory,
    required Map<String, Object?> payload,
    Future<void>? abortTrigger,
  }) async {
    final encoded = jsonEncode(payload);
    final boundedPayload = utf8.encode(encoded).length <= maxInputBytes
        ? encoded
        : jsonEncode({
            ...payload,
            'tool_input': {'truncated': true},
            'tool_output': payload['tool_output'] is String
                ? (payload['tool_output'] as String).substring(
                    0,
                    (payload['tool_output'] as String).length.clamp(0, 4096),
                  )
                : null,
          });
    Process? process;
    try {
      process = await Process.start(
        Platform.isWindows ? 'powershell.exe' : '/bin/sh',
        Platform.isWindows
            ? [
                '-NoLogo',
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                hook.command
              ]
            : ['-c', hook.command],
        workingDirectory: workingDirectory,
      );
      process.stdin.write(boundedPayload);
      await process.stdin.close();
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      var bytes = 0;
      void collect(StringBuffer buffer, String text) {
        final remaining = maxOutputBytes - bytes;
        if (remaining <= 0) return;
        final content = utf8.encode(text);
        buffer.write(utf8.decode(
          content.take(remaining).toList(growable: false),
          allowMalformed: true,
        ));
        bytes += content.length.clamp(0, remaining);
      }

      final stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (text) => collect(stdout, text),
            onDone: () => stdoutDone.complete(),
          );
      final stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (text) => collect(stderr, text),
            onDone: () => stderrDone.complete(),
          );
      final timeout = Completer<void>();
      final timer =
          Timer(Duration(seconds: hook.timeoutSeconds), timeout.complete);
      final Object outcome;
      try {
        outcome = await Future.any<Object>([
          process.exitCode,
          timeout.future.then((_) => -1),
          if (abortTrigger != null)
            abortTrigger.then((_) => const _HookCancelled()),
        ]);
      } finally {
        timer.cancel();
      }
      if (outcome is _HookCancelled) {
        process.kill();
        await Future.wait([stdoutDone.future, stderrDone.future]).timeout(
          const Duration(seconds: 2),
          onTimeout: () => const [],
        );
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
        return (
          exitCode: -2,
          text: 'Hook stopped because the agent response was cancelled.',
        );
      }
      if (outcome == -1) {
        process.kill();
        await Future.wait([stdoutDone.future, stderrDone.future]).timeout(
          const Duration(seconds: 2),
          onTimeout: () => const [],
        );
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
        return (
          exitCode: -1,
          text: 'Hook timed out after ${hook.timeoutSeconds} seconds.',
        );
      }
      final exitCode = outcome as int;
      try {
        await Future.wait([stdoutDone.future, stderrDone.future]).timeout(
          const Duration(seconds: 2),
        );
      } on TimeoutException {
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      }
      final text = [stdout.toString().trim(), stderr.toString().trim()]
          .where((value) => value.isNotEmpty)
          .join('\n');
      return (exitCode: exitCode, text: text);
    } on FileSystemException {
      process?.kill();
      return (exitCode: -1, text: 'The hook command could not be started.');
    } on ProcessException {
      process?.kill();
      return (exitCode: -1, text: 'The hook command could not be started.');
    }
  }
}

class _HookCancelled {
  const _HookCancelled();
}
