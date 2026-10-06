import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/task_progress_tool.dart';

void main() {
  test('validates and replaces the complete checklist', () {
    final update = parseTaskProgressArguments({
      'todos': [
        {'content': 'Inspect the project', 'status': 'completed'},
        {'content': 'Implement the fix', 'status': 'in_progress'},
        {'content': 'Run tests', 'status': 'pending'},
      ],
    });

    expect(update.isValid, isTrue);
    expect(update.todos, hasLength(3));
    expect(update.todos[0].status, ChatTaskStatus.completed);
    expect(update.todos[1].status, ChatTaskStatus.inProgress);
    expect(update.todos[2].status, ChatTaskStatus.pending);
    expect(taskProgressInstructions(update.todos),
        contains('Current task progress'));
    expect(taskProgressInstructions(update.todos), contains('in_progress'));
  });

  test('rejects malformed, duplicate, and oversized task updates', () {
    expect(
      parseTaskProgressArguments({
        'todos': [
          {'content': 'Inspect', 'status': 'pending'},
          {'content': 'inspect', 'status': 'completed'},
        ],
      }).isValid,
      isFalse,
    );
    expect(
      parseTaskProgressArguments({
        'todos': [
          {'content': '', 'status': 'pending'},
        ],
      }).isValid,
      isFalse,
    );
    expect(
      parseTaskProgressArguments({'todos': <Object?>[], 'other': true}).isValid,
      isFalse,
    );
    expect(
      parseTaskProgressArguments({
        'todos': List.generate(
            25,
            (index) => {
                  'content': 'Task $index',
                  'status': 'pending',
                }),
      }).isValid,
      isFalse,
    );
  });

  test('restores saved task status from JSON and ignores invalid items', () {
    expect(
      ChatTaskItem.fromJson({'content': 'Run checks', 'status': 'in_progress'})
          ?.status,
      ChatTaskStatus.inProgress,
    );
    expect(
      ChatTaskItem.fromJson({'content': 'Run checks', 'status': 'unknown'}),
      isNull,
    );
  });
}
