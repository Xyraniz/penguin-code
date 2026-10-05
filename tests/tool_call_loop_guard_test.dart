import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/tool_call_loop_guard.dart';

void main() {
  group('ToolCallLoopGuard', () {
    test('blocks a fifth call with deeply reordered JSON arguments', () {
      final guard = ToolCallLoopGuard();

      for (var attempt = 1; attempt < 5; attempt++) {
        final Map<String, dynamic> arguments = attempt.isEven
            ? {
                'options': {'reporter': 'expanded', 'verbose': true},
                'command': 'flutter test',
              }
            : {
                'command': 'flutter test',
                'options': {'verbose': true, 'reporter': 'expanded'},
              };
        expect(
          guard.inspect(_call('run_command', arguments)).blocked,
          isFalse,
        );
      }

      final blocked = guard.inspect(
        _call('run_command', {
          'command': 'flutter test',
          'options': {'reporter': 'expanded', 'verbose': true},
        }),
      );

      expect(blocked.blocked, isTrue);
      expect(blocked.consecutiveAttempts, 5);
    });

    test('allows different calls and starts a new repeat chain', () {
      final guard = ToolCallLoopGuard();
      guard.inspect(_call('read_project_file', {'path': 'README.md'}));
      guard.inspect(_call('read_project_file', {'path': 'README.md'}));

      final changedArguments = guard.inspect(
        _call('read_project_file', {'path': 'lib/main.dart'}),
      );
      final changedTool = guard.inspect(
        _call('search_project_files', {'query': 'Penguin'}),
      );

      expect(changedArguments.blocked, isFalse);
      expect(changedArguments.consecutiveAttempts, 1);
      expect(changedTool.blocked, isFalse);
      expect(changedTool.consecutiveAttempts, 1);
    });

    test('uses raw invalid JSON arguments to recognize exact retries', () {
      final guard = ToolCallLoopGuard();

      for (var attempt = 1; attempt <= 5; attempt++) {
        final decision = guard.inspect(
          AgentToolCall(
            id: 'invalid-$attempt',
            name: 'read_project_file',
            arguments: const {},
            rawArguments: '{invalid',
            hasValidArguments: false,
          ),
        );
        expect(decision.blocked, attempt == 5);
      }
    });

    test('a new guard starts with a fresh user response limit', () {
      final previousResponse = ToolCallLoopGuard();
      final nextResponse = ToolCallLoopGuard();
      final call = _call('run_command', {'command': 'flutter test'});

      previousResponse.inspect(call);
      previousResponse.inspect(call);
      previousResponse.inspect(call);
      previousResponse.inspect(call);

      for (var attempt = 1; attempt <= 4; attempt++) {
        expect(nextResponse.inspect(call).blocked, isFalse);
      }
      expect(nextResponse.inspect(call).blocked, isTrue);
    });
  });
}

AgentToolCall _call(String name, Map<String, dynamic> arguments) =>
    AgentToolCall(
      id: 'tool-call',
      name: name,
      arguments: arguments,
      rawArguments: '',
      hasValidArguments: true,
    );
