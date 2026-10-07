import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/services/project_init_command.dart';

void main() {
  test('recognizes only the standalone init command', () {
    expect(isProjectInitCommand('/init'), isTrue);
    expect(isProjectInitCommand('  /INIT  '), isTrue);
    expect(isProjectInitCommand('Please run /init'), isFalse);
    expect(isProjectInitCommand('/init project'), isFalse);
  });
}
