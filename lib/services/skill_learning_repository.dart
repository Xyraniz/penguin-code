import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models.dart';
import 'agent_data_store.dart';

enum SkillProposalAction { create, update }

class PendingSkillProposal {
  const PendingSkillProposal({
    required this.id,
    required this.action,
    required this.name,
    required this.description,
    required this.content,
    required this.createdAt,
    this.skillId,
    this.baseContent,
  });

  final String id;
  final SkillProposalAction action;
  final String name;
  final String description;
  final String content;
  final DateTime createdAt;
  final String? skillId;
  final String? baseContent;

  Map<String, Object?> toJson() => {
        'id': id,
        'action': action.name,
        'name': name,
        'description': description,
        'content': content,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'skillId': skillId,
        'baseContent': baseContent,
      };

  static PendingSkillProposal? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final actionName = value['action'];
    final name = value['name'];
    final description = value['description'];
    final content = value['content'];
    final createdAtValue = value['createdAt'];
    final skillId = value['skillId'];
    final baseContent = value['baseContent'];
    final action = SkillProposalAction.values
        .where((item) => item.name == actionName)
        .firstOrNull;
    final createdAt =
        createdAtValue is String ? DateTime.tryParse(createdAtValue) : null;
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        action == null ||
        name is! String ||
        name.isEmpty ||
        name.length > 80 ||
        description is! String ||
        description.isEmpty ||
        description.length > 280 ||
        content is! String ||
        content.contains('\u0000') ||
        utf8.encode(content).length > SkillLearningRepository.maxSkillBytes ||
        createdAt == null ||
        (skillId != null && skillId is! String) ||
        (baseContent != null && baseContent is! String) ||
        (action == SkillProposalAction.create &&
            (skillId != null || baseContent != null)) ||
        (action == SkillProposalAction.update &&
            (skillId is! String ||
                !skillId.startsWith('local:') ||
                baseContent is! String ||
                utf8.encode(baseContent).length >
                    SkillLearningRepository.maxSkillBytes))) {
      return null;
    }
    return PendingSkillProposal(
      id: id,
      action: action,
      name: name,
      description: description,
      content: content,
      createdAt: createdAt,
      skillId: skillId as String?,
      baseContent: baseContent as String?,
    );
  }
}

class SkillLearningException implements Exception {
  const SkillLearningException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SkillLearningRepository {
  static const maxSkillBytes = 32 * 1024;
  static const maxPendingProposals = 24;
  static final _slugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  static final _safeIdPattern = RegExp(r'^[a-f0-9]{32}$');
  final Random _random = Random.secure();

  Directory _pendingDirectory(Directory skillsDirectory) => Directory(
        '${skillsDirectory.path}${Platform.pathSeparator}Pending',
      );

  Future<List<PendingSkillProposal>> loadPending({
    required Directory skillsDirectory,
  }) async {
    if (await FileSystemEntity.type(
          skillsDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      return const [];
    }
    final directory = _pendingDirectory(skillsDirectory);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return const [];
    }
    final proposals = <PendingSkillProposal>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            !entity.path.toLowerCase().endsWith('.json') ||
            await FileSystemEntity.type(entity.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await entity.length() > 70 * 1024) {
          continue;
        }
        try {
          final proposal = PendingSkillProposal.fromJson(
            jsonDecode(await entity.readAsString()),
          );
          if (proposal != null) proposals.add(proposal);
        } on Object {
          // Ignore one damaged proposal without hiding the others.
        }
        if (proposals.length == maxPendingProposals) break;
      }
    } on FileSystemException {
      return const [];
    }
    proposals.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return List.unmodifiable(proposals);
  }

  Future<PendingSkillProposal> propose({
    required Map<String, dynamic> arguments,
    required Directory skillsDirectory,
    required List<AgentSkillProfile> installedSkills,
  }) async {
    const requiredKeys = {'action', 'name', 'description', 'procedure'};
    const allowedKeys = {...requiredKeys, 'skill_id'};
    final action = arguments['action'];
    final name = arguments['name'];
    final description = arguments['description'];
    final procedure = arguments['procedure'];
    final skillId = arguments['skill_id'];
    if (!arguments.keys.toSet().containsAll(requiredKeys) ||
        arguments.keys.any((key) => !allowedKeys.contains(key)) ||
        action is! String ||
        name is! String ||
        description is! String ||
        procedure is! String) {
      throw const SkillLearningException(
        'Provide an action, skill name, short description, and reusable procedure.',
      );
    }
    final proposalAction = switch (action) {
      'create' => SkillProposalAction.create,
      'update' => SkillProposalAction.update,
      _ => null,
    };
    if (proposalAction == null ||
        name.trim().isEmpty ||
        name.trim().length > 80 ||
        name.contains(RegExp(r'[\r\n\u0000]')) ||
        description.trim().isEmpty ||
        description.trim().length > 280 ||
        description.contains(RegExp(r'[\r\n\u0000]')) ||
        procedure.trim().isEmpty ||
        procedure.contains('\u0000')) {
      throw const SkillLearningException(
        'The skill title, description, and procedure are invalid or too long.',
      );
    }
    final normalizedName = name.trim();
    final normalizedDescription = description.trim();
    final normalizedProcedure = procedure.trim();
    if (AgentDataStore.containsSensitiveValue(
      '$normalizedName\n$normalizedDescription\n$normalizedProcedure',
    )) {
      throw const SkillLearningException(
        'Skill proposals cannot contain credentials or private keys.',
      );
    }
    final slug = _slug(normalizedName);
    if (!_slugPattern.hasMatch(slug)) {
      throw const SkillLearningException(
        'The skill name needs at least one English letter or number.',
      );
    }
    final skillContent = _buildSkillContent(
      normalizedName,
      normalizedDescription,
      normalizedProcedure,
    );
    if (utf8.encode(skillContent).length > maxSkillBytes) {
      throw const SkillLearningException(
        'Skill proposals must be 32 KiB or smaller.',
      );
    }
    await _ensureSkillsDirectory(skillsDirectory);

    String? targetSkillId;
    String? baseContent;
    if (proposalAction == SkillProposalAction.create) {
      if (skillId != null) {
        throw const SkillLearningException(
          'A new skill must not target an existing skill.',
        );
      }
      final destination = Directory(
        '${skillsDirectory.path}${Platform.pathSeparator}$slug',
      );
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const SkillLearningException(
          'A skill with this name already exists. Propose an update instead.',
        );
      }
    } else {
      if (skillId is! String || skillId.isEmpty) {
        throw const SkillLearningException(
          'Choose an installed local skill to update.',
        );
      }
      final skill = installedSkills
          .where((item) => item.id == skillId && !item.isBundled)
          .firstOrNull;
      if (skill == null) {
        throw const SkillLearningException(
          'Only an installed local skill can be updated.',
        );
      }
      final directory = await _installedSkillDirectory(skill, skillsDirectory);
      final file = File(
        '${directory.path}${Platform.pathSeparator}SKILL.md',
      );
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > maxSkillBytes) {
        throw const SkillLearningException(
          'The selected skill file is missing or exceeds the size limit.',
        );
      }
      try {
        baseContent = await file.readAsString();
      } on Object {
        throw const SkillLearningException(
          'The selected skill file is not valid UTF-8 text.',
        );
      }
      targetSkillId = skill.id;
    }

    final pending = await loadPending(skillsDirectory: skillsDirectory);
    if (pending.length >= maxPendingProposals) {
      throw const SkillLearningException(
        'Review or remove pending skill proposals before adding another.',
      );
    }
    if (pending.any((item) => proposalAction == SkillProposalAction.create
        ? item.action == SkillProposalAction.create && _slug(item.name) == slug
        : item.action == SkillProposalAction.update &&
            item.skillId == targetSkillId)) {
      throw const SkillLearningException(
        'A proposal for this skill is already waiting for review.',
      );
    }
    final pendingDirectory = _pendingDirectory(skillsDirectory);
    if (await FileSystemEntity.type(pendingDirectory.path,
            followLinks: false) ==
        FileSystemEntityType.link) {
      throw const SkillLearningException(
        'The pending skill folder cannot be a symbolic link.',
      );
    }
    await pendingDirectory.create(recursive: true);
    final id = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final proposal = PendingSkillProposal(
      id: id,
      action: proposalAction,
      name: normalizedName,
      description: normalizedDescription,
      content: skillContent,
      createdAt: DateTime.now().toUtc(),
      skillId: targetSkillId,
      baseContent: baseContent,
    );
    final destination = File(
      '${pendingDirectory.path}${Platform.pathSeparator}$id.json',
    );
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(proposal.toJson()), flush: true);
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return proposal;
  }

  Future<void> approve({
    required String proposalId,
    required Directory skillsDirectory,
    required List<AgentSkillProfile> installedSkills,
  }) async {
    final proposal = await _readProposal(proposalId, skillsDirectory);
    if (AgentDataStore.containsSensitiveValue(proposal.content)) {
      throw const SkillLearningException(
        'This proposal contains a credential-like value and cannot be installed.',
      );
    }
    if (proposal.action == SkillProposalAction.create) {
      final slug = _slug(proposal.name);
      final destination = Directory(
        '${skillsDirectory.path}${Platform.pathSeparator}$slug',
      );
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const SkillLearningException(
          'A skill with this name was added while this proposal was pending.',
        );
      }
      final temporary = Directory(
        '${skillsDirectory.path}${Platform.pathSeparator}.proposal-$proposalId',
      );
      try {
        await temporary.create();
        await File(
          '${temporary.path}${Platform.pathSeparator}SKILL.md',
        ).writeAsString(proposal.content, flush: true);
        await File(
          '${temporary.path}${Platform.pathSeparator}.penguin-skill.json',
        ).writeAsString(
          jsonEncode({
            'source': 'Created with Penguin Code skill learning',
            'createdAt': proposal.createdAt.toIso8601String(),
          }),
          flush: true,
        );
        await temporary.rename(destination.path);
      } on FileSystemException {
        if (await temporary.exists()) await temporary.delete(recursive: true);
        rethrow;
      }
    } else {
      final skill = installedSkills
          .where((item) => item.id == proposal.skillId && !item.isBundled)
          .firstOrNull;
      if (skill == null) {
        throw const SkillLearningException(
          'The skill to update is no longer installed.',
        );
      }
      final directory = await _installedSkillDirectory(skill, skillsDirectory);
      final file = File(
        '${directory.path}${Platform.pathSeparator}SKILL.md',
      );
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const SkillLearningException(
          'The skill file is missing or is a symbolic link.',
        );
      }
      if (await file.length() > maxSkillBytes) {
        throw const SkillLearningException(
          'The current skill file exceeds the size limit.',
        );
      }
      final currentContent = await file.readAsString();
      if (currentContent != proposal.baseContent) {
        if (currentContent == proposal.content) {
          await _deleteProposal(proposalId, skillsDirectory);
          return;
        }
        throw const SkillLearningException(
          'The skill changed after this proposal was created. Refresh Skills and review a new proposal.',
        );
      }
      final temporary = File(
        '${file.path}.proposal-$proposalId.tmp',
      );
      final backup = File('${file.path}.proposal-$proposalId.bak');
      try {
        if (await FileSystemEntity.type(backup.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const SkillLearningException(
            'A temporary skill backup already exists.',
          );
        }
        await temporary.writeAsString(proposal.content, flush: true);
        await file.rename(backup.path);
        try {
          await temporary.rename(file.path);
        } on FileSystemException {
          if (await FileSystemEntity.type(file.path, followLinks: false) ==
                  FileSystemEntityType.notFound &&
              await FileSystemEntity.type(backup.path, followLinks: false) ==
                  FileSystemEntityType.file) {
            await backup.rename(file.path);
          }
          rethrow;
        }
        await backup.delete();
      } on FileSystemException {
        if (await temporary.exists()) await temporary.delete();
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
                FileSystemEntityType.notFound &&
            await FileSystemEntity.type(backup.path, followLinks: false) ==
                FileSystemEntityType.file) {
          await backup.rename(file.path);
        }
        rethrow;
      }
    }
    await _deleteProposal(proposalId, skillsDirectory);
  }

  Future<void> reject({
    required String proposalId,
    required Directory skillsDirectory,
  }) async {
    await _readProposal(proposalId, skillsDirectory);
    await _deleteProposal(proposalId, skillsDirectory);
  }

  Future<PendingSkillProposal> _readProposal(
    String id,
    Directory skillsDirectory,
  ) async {
    if (!_safeIdPattern.hasMatch(id)) {
      throw const SkillLearningException('The skill proposal id is invalid.');
    }
    if (await FileSystemEntity.type(
          skillsDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      throw const SkillLearningException(
        'This skill proposal is no longer available.',
      );
    }
    final pendingDirectory = _pendingDirectory(skillsDirectory);
    if (await FileSystemEntity.type(
          pendingDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      throw const SkillLearningException(
        'This skill proposal is no longer available.',
      );
    }
    final file = File(
      '${pendingDirectory.path}${Platform.pathSeparator}$id.json',
    );
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const SkillLearningException(
        'This skill proposal is no longer available.',
      );
    }
    if (await file.length() > 70 * 1024) {
      throw const SkillLearningException('This skill proposal is invalid.');
    }
    final PendingSkillProposal? value;
    try {
      value = PendingSkillProposal.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } on FormatException {
      throw const SkillLearningException('This skill proposal is invalid.');
    }
    if (value == null || value.id != id) {
      throw const SkillLearningException('This skill proposal is invalid.');
    }
    return value;
  }

  Future<void> _deleteProposal(String id, Directory skillsDirectory) async {
    if (!_safeIdPattern.hasMatch(id)) {
      throw const SkillLearningException('The skill proposal id is invalid.');
    }
    final directory = _pendingDirectory(skillsDirectory);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await file.delete();
    }
  }

  Future<Directory> _installedSkillDirectory(
    AgentSkillProfile skill,
    Directory skillsDirectory,
  ) async {
    final path = skill.directoryPath;
    if (path == null || skill.id != 'local:${_basename(path).toLowerCase()}') {
      throw const SkillLearningException(
        'The selected skill folder is invalid.',
      );
    }
    final directory = Directory(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory ||
        _normalizePath(directory.parent.absolute.path) !=
            _normalizePath(skillsDirectory.absolute.path)) {
      throw const SkillLearningException(
        'The selected skill must be a direct local skill folder.',
      );
    }
    return directory;
  }

  Future<void> _ensureSkillsDirectory(Directory skillsDirectory) async {
    await skillsDirectory.create(recursive: true);
    if (await FileSystemEntity.type(
          skillsDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      throw const SkillLearningException(
        'The skills folder cannot be a symbolic link.',
      );
    }
  }

  String _buildSkillContent(
          String name, String description, String procedure) =>
      '---\nname: ${jsonEncode(name)}\ndescription: ${jsonEncode(description)}\n---\n# $name\n\n## When to Use\n$description\n\n## Procedure\n$procedure\n';

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  String _basename(String path) =>
      path
          .split(RegExp(r'[/\\]'))
          .where((part) => part.isNotEmpty)
          .lastOrNull ??
      '';

  String _normalizePath(String path) => Platform.isWindows
      ? path.replaceAll('/', '\\').replaceAll(RegExp(r'\\+$'), '').toLowerCase()
      : path.replaceAll(RegExp(r'/+$'), '');
}
