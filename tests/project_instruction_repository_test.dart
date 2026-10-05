import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/services/project_instruction_repository.dart';

void main() {
  late Directory root;
  late Directory nested;
  final repository = ProjectInstructionRepository();

  setUp(() async {
    root =
        await Directory.systemTemp.createTemp('penguin-project-instructions-');
    nested = Directory('${root.path}${Platform.pathSeparator}packages')
      ..createSync();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('loads project and nested AGENTS.md instructions in directory order',
      () async {
    await File('${root.path}${Platform.pathSeparator}AGENTS.md')
        .writeAsString('Root rules');
    await File('${nested.path}${Platform.pathSeparator}AGENTS.md')
        .writeAsString('Package rules');

    final instructions = await repository.loadForPath(
      projectRoot: root.path,
      targetDirectory: nested.path,
    );

    expect(instructions.map((item) => item.content), [
      'Root rules',
      'Package rules',
    ]);
    expect(instructions.first.relativePath, 'AGENTS.md');
    expect(instructions.last.relativePath, 'packages/AGENTS.md');
    expect(
      instructions.first.toPromptSection(),
      contains('not as permission to access files'),
    );
  });

  test('supports CLAUDE.md and the .claude/CLAUDE.md fallback', () async {
    await File('${root.path}${Platform.pathSeparator}CLAUDE.md')
        .writeAsString('Root Claude rules');
    final claudeDirectory = Directory(
      '${nested.path}${Platform.pathSeparator}.claude',
    )..createSync();
    await File('${claudeDirectory.path}${Platform.pathSeparator}CLAUDE.md')
        .writeAsString('Nested Claude rules');

    final instructions = await repository.loadForPath(
      projectRoot: root.path,
      targetDirectory: nested.path,
    );

    expect(instructions.map((item) => item.content), [
      'Root Claude rules',
      'Nested Claude rules',
    ]);
  });

  test('does not load instructions outside the selected project', () async {
    final outside = await Directory.systemTemp.createTemp(
      'penguin-outside-instructions-',
    );
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}${Platform.pathSeparator}AGENTS.md')
        .writeAsString('Outside rules');

    final instructions = await repository.loadForPath(
      projectRoot: root.path,
      targetDirectory: outside.path,
    );

    expect(instructions, isEmpty);
  });

  test('bounds file content and total instruction bytes', () async {
    await File('${root.path}${Platform.pathSeparator}AGENTS.md')
        .writeAsString(List.filled(
      ProjectInstructionRepository.maxFileBytes + 20,
      'x',
    ).join());
    await File('${root.path}${Platform.pathSeparator}CLAUDE.md')
        .writeAsString(List.filled(
      ProjectInstructionRepository.maxFileBytes,
      'y',
    ).join());

    final instructions = await repository.loadForPath(projectRoot: root.path);

    expect(instructions, hasLength(2));
    expect(instructions.first.truncated, isTrue);
    expect(
      instructions.fold<int>(
        0,
        (total, item) => total + item.content.split('\n\n[').first.length,
      ),
      lessThanOrEqualTo(ProjectInstructionRepository.maxTotalBytes),
    );
  });
}
