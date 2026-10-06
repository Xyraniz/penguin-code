import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/skill_learning_repository.dart';

void main() {
  late Directory root;
  late Directory skillsDirectory;
  late SkillLearningRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('penguin-skill-learning-');
    skillsDirectory = Directory('${root.path}${Platform.pathSeparator}Skills');
    await skillsDirectory.create();
    repository = SkillLearningRepository();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('stages new skills until explicit approval', () async {
    final proposal = await repository.propose(
      arguments: _createArguments(),
      skillsDirectory: skillsDirectory,
      installedSkills: const [],
    );

    expect(
        await File('${skillsDirectory.path}/careful-review/SKILL.md').exists(),
        isFalse);
    final staged =
        await repository.loadPending(skillsDirectory: skillsDirectory);
    expect(staged, hasLength(1));
    expect(staged.single.id, proposal.id);

    await repository.approve(
      proposalId: proposal.id,
      skillsDirectory: skillsDirectory,
      installedSkills: const [],
    );

    final installed = File('${skillsDirectory.path}/careful-review/SKILL.md');
    expect(
        await installed.readAsString(), contains('Check the changed files.'));
    expect(
      Directory('${skillsDirectory.path}/careful-review')
          .listSync()
          .map((entity) => entity.uri.pathSegments.last)
          .toSet(),
      {'SKILL.md', '.penguin-skill.json'},
    );
    expect(await repository.loadPending(skillsDirectory: skillsDirectory),
        isEmpty);
  });

  test('rejects a proposal without installing it', () async {
    final proposal = await repository.propose(
      arguments: _createArguments(),
      skillsDirectory: skillsDirectory,
      installedSkills: const [],
    );

    await repository.reject(
      proposalId: proposal.id,
      skillsDirectory: skillsDirectory,
    );

    expect(await Directory('${skillsDirectory.path}/careful-review').exists(),
        isFalse);
    expect(await repository.loadPending(skillsDirectory: skillsDirectory),
        isEmpty);
  });

  test('updates only the reviewed version of a local skill', () async {
    final skillDirectory = Directory('${skillsDirectory.path}/review-workflow');
    await skillDirectory.create();
    final skillFile = File('${skillDirectory.path}/SKILL.md');
    await skillFile.writeAsString('# Review workflow\n\nOld instructions.');
    final skill = AgentSkillProfile(
      id: 'local:review-workflow',
      name: 'Review workflow',
      description: 'Review code changes.',
      triggerText: 'review code',
      isBundled: false,
      directoryPath: skillDirectory.path,
    );
    final proposal = await repository.propose(
      arguments: {
        'action': 'update',
        'skill_id': skill.id,
        'name': skill.name,
        'description': skill.description,
        'procedure': 'Check the diff and report concrete risks.',
      },
      skillsDirectory: skillsDirectory,
      installedSkills: [skill],
    );
    await skillFile.writeAsString('# Review workflow\n\nChanged elsewhere.');

    await expectLater(
      repository.approve(
        proposalId: proposal.id,
        skillsDirectory: skillsDirectory,
        installedSkills: [skill],
      ),
      throwsA(isA<SkillLearningException>()),
    );
    expect(await skillFile.readAsString(), contains('Changed elsewhere.'));
    expect(await repository.loadPending(skillsDirectory: skillsDirectory),
        hasLength(1));
  });

  test('approves an update and preserves local metadata', () async {
    final skillDirectory = Directory('${skillsDirectory.path}/review-workflow');
    await skillDirectory.create();
    final skillFile = File('${skillDirectory.path}/SKILL.md');
    await skillFile.writeAsString('# Review workflow\n\nOld instructions.');
    final metadata = File('${skillDirectory.path}/.penguin-skill.json');
    await metadata.writeAsString('{"source":"local folder"}');
    final skill = AgentSkillProfile(
      id: 'local:review-workflow',
      name: 'Review workflow',
      description: 'Review code changes.',
      triggerText: 'review code',
      isBundled: false,
      directoryPath: skillDirectory.path,
    );
    final proposal = await repository.propose(
      arguments: {
        'action': 'update',
        'skill_id': skill.id,
        'name': skill.name,
        'description': skill.description,
        'procedure': 'Check the diff and report concrete risks.',
      },
      skillsDirectory: skillsDirectory,
      installedSkills: [skill],
    );

    await repository.approve(
      proposalId: proposal.id,
      skillsDirectory: skillsDirectory,
      installedSkills: [skill],
    );

    expect(await skillFile.readAsString(), proposal.content);
    expect(await metadata.readAsString(), '{"source":"local folder"}');
    expect(await repository.loadPending(skillsDirectory: skillsDirectory),
        isEmpty);
  });

  test('rejects credential-like values and malformed action targets', () async {
    await expectLater(
      repository.propose(
        arguments: _createArguments()
          ..['procedure'] = 'Store API_KEY=private-value in the project.',
        skillsDirectory: skillsDirectory,
        installedSkills: const [],
      ),
      throwsA(isA<SkillLearningException>()),
    );

    await expectLater(
      repository.propose(
        arguments: {
          ..._createArguments(),
          'skill_id': 'local:someone-elses-skill',
        },
        skillsDirectory: skillsDirectory,
        installedSkills: const [],
      ),
      throwsA(isA<SkillLearningException>()),
    );
    expect(await repository.loadPending(skillsDirectory: skillsDirectory),
        isEmpty);
  });

  test('does not follow a linked pending directory', () async {
    final outside = Directory('${root.path}/outside')..createSync();
    final pending = Directory('${skillsDirectory.path}/Pending');
    try {
      await Link(pending.path).create(outside.path, recursive: true);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable on this test host.');
    }

    await expectLater(
      repository.propose(
        arguments: _createArguments(),
        skillsDirectory: skillsDirectory,
        installedSkills: const [],
      ),
      throwsA(isA<SkillLearningException>()),
    );
    expect(outside.listSync(), isEmpty);
  });
}

Map<String, dynamic> _createArguments() => {
      'action': 'create',
      'name': 'Careful review',
      'description': 'Review code changes before delivery.',
      'procedure': 'Check the changed files. Report concrete risks.',
    };
