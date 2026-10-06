import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/goal_command.dart';

void main() {
  test('parses goal lifecycle commands without consuming ordinary messages',
      () {
    expect(parseGoalCommand('Please /goal finish this'), isNull);
    expect(parseGoalCommand('/goal')?.kind, GoalCommandKind.status);
    expect(parseGoalCommand('/goal clear')?.kind, GoalCommandKind.clear);
    expect(parseGoalCommand('/goal pause')?.kind, GoalCommandKind.pause);
    expect(parseGoalCommand('/goal resume')?.kind, GoalCommandKind.resume);
    expect(
      parseGoalCommand('/goal edit run the full test suite')?.objective,
      'run the full test suite',
    );
    expect(
      parseGoalCommand('/goal all widget tests pass')?.objective,
      'all widget tests pass',
    );
    expect(parseGoalCommand('/goal edit')?.kind, GoalCommandKind.invalid);
    expect(
      parseGoalCommand('/goal ${'x' * (maxGoalCharacters + 1)}')?.kind,
      GoalCommandKind.invalid,
    );
  });

  test('accepts only explicit evaluator verdicts with concise reasons', () {
    final notYetMet =
        parseGoalEvaluation('VERDICT: not_yet_met\nREASON: Run the tests.');
    expect(notYetMet?.verdict, GoalVerdict.notYetMet);
    expect(notYetMet?.reason, 'Run the tests.');
    final met = parseGoalEvaluation(
      'VERDICT: met\nREASON: The requested tests passed.',
    );
    expect(met?.verdict, GoalVerdict.met);
    expect(met?.reason, 'The requested tests passed.');
    final impossible = parseGoalEvaluation(
      'VERDICT: impossible\nREASON: The provider is unavailable.',
    );
    expect(impossible?.verdict, GoalVerdict.impossible);
    expect(impossible?.reason, 'The provider is unavailable.');
    expect(parseGoalEvaluation('Looks good to me.'), isNull);
    expect(parseGoalEvaluation('VERDICT: met\nREASON: '), isNull);
  });

  test('round trips bounded goal state', () {
    const goal = ChatGoal(
      objective: 'All checks pass',
      status: ChatGoalStatus.paused,
      evaluatedTurns: 3,
      lastReason: 'One test is still failing.',
    );

    expect(ChatGoal.fromJson(goal.toJson())?.objective, goal.objective);
    expect(ChatGoal.fromJson(goal.toJson())?.status, goal.status);
    expect(ChatGoal.fromJson(goal.toJson())?.evaluatedTurns, 3);
    expect(ChatGoal.fromJson(goal.toJson())?.lastReason, goal.lastReason);
    expect(ChatGoal.fromJson({'objective': 'x' * 4001, 'status': 'active'}),
        isNull);
  });
}
