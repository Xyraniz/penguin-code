import 'dart:convert';
import 'dart:io';

import '../models.dart';

class SavedConversation {
  const SavedConversation({
    required this.conversation,
    required this.messages,
    this.agentTask,
  });

  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final AgentTask? agentTask;
}

class ChatDirectories {
  const ChatDirectories({
    required this.root,
    required this.workspace,
    required this.outputs,
  });

  final Directory root;
  final Directory workspace;
  final Directory outputs;
}

class AgentMemoryUpdateResult {
  const AgentMemoryUpdateResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class AgentDataStore {
  AgentDataStore({Directory? documentsDirectory, Directory? fallbackDirectory})
      : _documentsDirectory = documentsDirectory,
        _fallbackDirectory = fallbackDirectory;

  static const maxMemoryBytes = 16 * 1024;
  static const maxContextSummaryChars = 24000;
  static const maxRememberedPreferences = 80;
  static const maxMemoryEntries = 80;
  static const maxMemoryEntryCharacters = 1000;
  static const _userProfileFileName = 'USER.md';
  static const _agentMemoryFileName = 'MEMORY.md';
  static const _legacyMemoryFileName = 'Memories.md';

  final Directory? _documentsDirectory;
  final Directory? _fallbackDirectory;
  final Map<String, Future<void>> _pendingWrites = {};
  Directory? _root;
  Future<void>? _initializing;

  String? get rootPath => _root?.path;
  bool get usedFallbackLocation =>
      _root != null && _root!.path != _primaryRoot.path;

  Directory get _primaryRoot => Directory(
        _join([_documents().path, 'Penguin-code']),
      );

  File get userProfileFile =>
      File(_join([_requireRoot().path, _userProfileFileName]));

  File get agentMemoryFile =>
      File(_join([_requireRoot().path, _agentMemoryFileName]));

  Directory get skillsDirectory =>
      Directory(_join([_requireRoot().path, 'Skills']));

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final primary = _primaryRoot;
    final root = _looksLikeSourceCheckout(primary)
        ? (_fallbackDirectory ?? _defaultFallbackDirectory())
        : primary;
    _root = root;
    await Directory(_join([root.path, 'Chats'])).create(recursive: true);
    await skillsDirectory.create(recursive: true);
    await _migrateLegacyMemories();
    if (!userProfileFile.existsSync()) {
      await userProfileFile.writeAsString(
        '# User profile\n\n## User preferences\n',
        flush: true,
      );
    }
    if (!agentMemoryFile.existsSync()) {
      await agentMemoryFile.writeAsString(
        '# Penguin Code memory\n\n## Learned notes\n',
        flush: true,
      );
    }
  }

  Future<void> _migrateLegacyMemories() async {
    final legacy = File(_join([_requireRoot().path, _legacyMemoryFileName]));
    if (!legacy.existsSync()) return;
    if (!userProfileFile.existsSync()) {
      final contents = await legacy.readAsString();
      await userProfileFile.writeAsString(contents, flush: true);
      await legacy.delete();
      return;
    }
    final oldContents = (await legacy.readAsString()).trim();
    if (oldContents.isNotEmpty) {
      final currentContents = await userProfileFile.readAsString();
      if (!currentContents.contains(oldContents)) {
        await userProfileFile.writeAsString(
          '${currentContents.trimRight()}\n\n## Imported notes\n$oldContents\n',
          flush: true,
        );
      }
    }
    await legacy.delete();
  }

  Directory _documents() {
    if (_documentsDirectory != null) return _documentsDirectory;
    final environment = Platform.environment;
    final home =
        Platform.isWindows ? environment['USERPROFILE'] : environment['HOME'];
    final profile =
        home?.trim().isNotEmpty == true ? home! : Directory.current.path;
    final standard = Directory(_join([profile, 'Documents']));
    if (standard.existsSync()) return standard;
    final oneDrive = environment['OneDrive']?.trim();
    if (oneDrive != null && oneDrive.isNotEmpty) {
      final redirected = Directory(_join([oneDrive, 'Documents']));
      if (redirected.existsSync()) return redirected;
    }
    return standard;
  }

  Directory _defaultFallbackDirectory() {
    final environment = Platform.environment;
    final parent = Platform.isWindows
        ? environment['APPDATA'] ?? environment['LOCALAPPDATA']
        : environment['XDG_DATA_HOME'] ??
            _join([
              environment['HOME'] ?? Directory.current.path,
              '.local',
              'share'
            ]);
    return Directory(
        _join([parent ?? Directory.systemTemp.path, 'Penguin Code']));
  }

  bool _looksLikeSourceCheckout(Directory directory) =>
      File(_join([directory.path, 'pubspec.yaml'])).existsSync() &&
      Directory(_join([directory.path, 'lib'])).existsSync() &&
      Directory(_join([directory.path, 'windows'])).existsSync();

  Future<ChatDirectories> directoriesFor(ChatConversation conversation) async {
    await initialize();
    final chatRoot = Directory(_join([
      _requireRoot().path,
      'Chats',
      _dateKey(_createdAt(conversation)),
      _safePathSegment(conversation.id),
    ]));
    final outputs = Directory(_join([chatRoot.path, 'outputs']));
    await outputs.create(recursive: true);
    final workspace = Directory(_join([chatRoot.path, 'workspace']));
    if (conversation.projectPath == null ||
        conversation.projectPath!.trim().isEmpty) {
      await workspace.create(recursive: true);
    }
    return ChatDirectories(
      root: chatRoot,
      workspace: workspace,
      outputs: outputs,
    );
  }

  Future<String> workingDirectoryFor(ChatConversation conversation) async {
    final projectPath = conversation.projectPath?.trim();
    if (projectPath != null && projectPath.isNotEmpty) return projectPath;
    return (await directoriesFor(conversation)).workspace.path;
  }

  Future<String> outputDirectoryFor(ChatConversation conversation) async =>
      (await directoriesFor(conversation)).outputs.path;

  String? workingDirectoryPathFor(ChatConversation conversation) {
    final projectPath = conversation.projectPath?.trim();
    if (projectPath != null && projectPath.isNotEmpty) return projectPath;
    final root = _root;
    if (root == null) return null;
    return _join([
      root.path,
      'Chats',
      _dateKey(_createdAt(conversation)),
      _safePathSegment(conversation.id),
      'workspace',
    ]);
  }

  String? outputDirectoryPathFor(ChatConversation conversation) {
    final root = _root;
    if (root == null) return null;
    return _join([
      root.path,
      'Chats',
      _dateKey(_createdAt(conversation)),
      _safePathSegment(conversation.id),
      'outputs',
    ]);
  }

  Future<void> saveConversation(
    ChatConversation conversation,
    List<ChatMessage> messages, {
    AgentTask? agentTask,
  }) async {
    final previous = _pendingWrites[conversation.id] ?? Future<void>.value();
    final next =
        previous.catchError((Object _) {}).then((_) => _writeConversation(
              conversation,
              messages,
              agentTask: agentTask,
            ));
    _pendingWrites[conversation.id] = next;
    try {
      await next;
    } finally {
      if (identical(_pendingWrites[conversation.id], next)) {
        _pendingWrites.remove(conversation.id);
      }
    }
  }

  Future<void> _writeConversation(
    ChatConversation conversation,
    List<ChatMessage> messages, {
    AgentTask? agentTask,
  }) async {
    final directories = await directoriesFor(conversation);
    final file = File(_join([directories.root.path, 'chat.json']));
    final tempFile = File('${file.path}.tmp');
    final payload = {
      'schemaVersion': 1,
      'conversation': _conversationToJson(conversation),
      'messages': messages.map(_messageToJson).toList(growable: false),
      if (agentTask != null) 'agentTask': agentTask.toJson(),
    };
    await tempFile.writeAsString(jsonEncode(payload), flush: true);
    if (file.existsSync()) await file.delete();
    await tempFile.rename(file.path);
  }

  Future<List<SavedConversation>> loadConversations() async {
    await initialize();
    final chatsRoot = Directory(_join([_requireRoot().path, 'Chats']));
    final result = <SavedConversation>[];
    try {
      await for (final day in chatsRoot.list(followLinks: false)) {
        if (day is! Directory ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                .hasMatch(_lastPathSegment(day.path))) {
          continue;
        }
        await for (final chatDirectory in day.list(followLinks: false)) {
          if (chatDirectory is! Directory) continue;
          final file = File(_join([chatDirectory.path, 'chat.json']));
          if (!file.existsSync()) continue;
          try {
            final decoded = jsonDecode(await file.readAsString());
            if (decoded is! Map<dynamic, dynamic> ||
                decoded['conversation'] is! Map<dynamic, dynamic> ||
                decoded['messages'] is! List) {
              continue;
            }
            final conversation = _conversationFromJson(
              Map<String, dynamic>.from(
                decoded['conversation'] as Map<dynamic, dynamic>,
              ),
            );
            final messages = (decoded['messages'] as List)
                .whereType<Map<dynamic, dynamic>>()
                .map((value) => _messageFromJson(
                      Map<String, dynamic>.from(value),
                    ))
                .toList(growable: true);
            final savedTask = AgentTask.fromJson(decoded['agentTask']);
            result.add(SavedConversation(
              conversation: conversation,
              messages: messages,
              agentTask: savedTask?.id == conversation.id ? savedTask : null,
            ));
          } on Object {
            // A damaged chat is skipped without hiding the remaining history.
          }
        }
      }
    } on FileSystemException {
      return const [];
    }
    result.sort((left, right) => _createdAt(right.conversation)
        .compareTo(_createdAt(left.conversation)));
    return result;
  }

  Future<void> removeConversationRecord(ChatConversation conversation) async {
    await _pendingWrites[conversation.id]?.catchError((Object _) {});
    final directories = await directoriesFor(conversation);
    final file = File(_join([directories.root.path, 'chat.json']));
    if (file.existsSync()) await file.delete();
  }

  Future<String> readUserProfile() async {
    await initialize();
    return userProfileFile.readAsString();
  }

  Future<String> readAgentMemory() async {
    await initialize();
    return agentMemoryFile.readAsString();
  }

  Future<void> writeUserProfile(String value) async {
    await initialize();
    await _writeMemoryFile(userProfileFile, value, 'User profile');
  }

  Future<void> writeAgentMemory(String value) async {
    await initialize();
    await _writeMemoryFile(agentMemoryFile, value, 'Agent memory');
  }

  Future<void> _writeMemoryFile(File file, String value, String label) async {
    await initialize();
    final bytes = utf8.encode(value);
    if (bytes.length > maxMemoryBytes) {
      throw FileSystemException('$label exceeds the 16 KiB limit.');
    }
    await file.writeAsString(value, flush: true);
  }

  Future<bool> rememberExplicitUserPreference(String message) async {
    final candidate = _explicitPreference(message);
    if (candidate == null) return false;
    final existing = await readUserProfile();
    final normalizedCandidate = _normalizeForComparison(candidate);
    final existingLines = existing.split('\n');
    if (existingLines.any((line) =>
        _normalizeForComparison(line.replaceFirst(RegExp(r'^\s*-\s*'), '')) ==
        normalizedCandidate)) {
      return false;
    }
    final sectionStart = existingLines.indexWhere(
      (line) => line.trim().toLowerCase() == '## user preferences',
    );
    if (sectionStart < 0) {
      existingLines
        ..add('')
        ..add('## User preferences')
        ..add('- $candidate');
    } else {
      var sectionEnd = existingLines.length;
      for (var index = sectionStart + 1;
          index < existingLines.length;
          index++) {
        if (RegExp(r'^#{1,2}\s').hasMatch(existingLines[index])) {
          sectionEnd = index;
          break;
        }
      }
      final preferenceIndexes = [
        for (var index = sectionStart + 1; index < sectionEnd; index++)
          if (existingLines[index].trimLeft().startsWith('- ')) index,
      ];
      if (preferenceIndexes.length >= maxRememberedPreferences) {
        existingLines.removeAt(preferenceIndexes.first);
        sectionEnd--;
      }
      existingLines.insert(sectionEnd, '- $candidate');
    }
    var updated = '${existingLines.join('\n').trimRight()}\n';
    while (utf8.encode(updated).length > maxMemoryBytes) {
      final candidateIndex = existingLines.indexWhere((line) =>
          line.trimLeft().startsWith('- ') &&
          _normalizeForComparison(line) == normalizedCandidate);
      final oldestPreferenceIndex = existingLines.indexWhere((line) =>
          line.trimLeft().startsWith('- ') &&
          _normalizeForComparison(line) != normalizedCandidate);
      if (oldestPreferenceIndex < 0 || candidateIndex < 0) return false;
      existingLines.removeAt(oldestPreferenceIndex);
      updated = '${existingLines.join('\n').trimRight()}\n';
    }
    await writeUserProfile(updated);
    return true;
  }

  Future<AgentMemoryUpdateResult> applyMemoryOperation({
    required String action,
    required String target,
    String? content,
    String? oldText,
  }) async {
    await initialize();
    if (!const {'user', 'memory'}.contains(target)) {
      return const AgentMemoryUpdateResult(
        success: false,
        message: 'Memory target must be "user" or "memory".',
      );
    }
    if (!const {'add', 'replace', 'remove'}.contains(action)) {
      return const AgentMemoryUpdateResult(
        success: false,
        message: 'Memory action must be add, replace, or remove.',
      );
    }
    final normalizedContent =
        content == null ? null : content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (action != 'remove' &&
        (normalizedContent == null ||
            normalizedContent.isEmpty ||
            normalizedContent.length > maxMemoryEntryCharacters ||
            containsSensitiveValue(normalizedContent))) {
      return const AgentMemoryUpdateResult(
        success: false,
        message:
            'Memory entries must be 1 to $maxMemoryEntryCharacters characters and must not contain credentials.',
      );
    }
    final normalizedOldText = oldText?.trim();
    if (action != 'add' &&
        (normalizedOldText == null ||
            normalizedOldText.isEmpty ||
            normalizedOldText.length > maxMemoryEntryCharacters)) {
      return const AgentMemoryUpdateResult(
        success: false,
        message:
            'Provide a short old_text value to identify one existing entry.',
      );
    }

    final file = target == 'user' ? userProfileFile : agentMemoryFile;
    final fileName =
        target == 'user' ? _userProfileFileName : _agentMemoryFileName;
    final existing = await file.readAsString();
    final lines = existing.split('\n');
    if (action == 'add') {
      final duplicate = lines.any((line) =>
          line.trimLeft().startsWith('- ') &&
          _normalizeForComparison(line) ==
              _normalizeForComparison(normalizedContent!));
      if (duplicate) {
        return AgentMemoryUpdateResult(
          success: true,
          message: 'That entry is already saved in $fileName.',
        );
      }
      final entryIndexes = [
        for (var index = 0; index < lines.length; index++)
          if (lines[index].trimLeft().startsWith('- ')) index,
      ];
      if (entryIndexes.length >= maxMemoryEntries) {
        return AgentMemoryUpdateResult(
          success: false,
          message:
              '$fileName already has $maxMemoryEntries entries. Remove or replace an older entry first.',
        );
      }
      final sectionTitle =
          target == 'user' ? '## User preferences' : '## Learned notes';
      final sectionStart = lines.indexWhere(
        (line) => line.trim().toLowerCase() == sectionTitle.toLowerCase(),
      );
      if (sectionStart < 0) {
        lines
          ..add('')
          ..add(sectionTitle)
          ..add('- $normalizedContent');
      } else {
        var sectionEnd = lines.length;
        for (var index = sectionStart + 1; index < lines.length; index++) {
          if (RegExp(r'^#{1,2}\s').hasMatch(lines[index])) {
            sectionEnd = index;
            break;
          }
        }
        lines.insert(sectionEnd, '- $normalizedContent');
      }
    } else {
      final matchedIndexes = [
        for (var index = 0; index < lines.length; index++)
          if (lines[index].trimLeft().startsWith('- ') &&
              lines[index]
                  .substring(lines[index].indexOf('- ') + 2)
                  .contains(normalizedOldText!))
            index,
      ];
      if (matchedIndexes.length != 1) {
        return AgentMemoryUpdateResult(
          success: false,
          message: matchedIndexes.isEmpty
              ? 'No unique entry matched old_text in $fileName.'
              : 'old_text matched multiple entries in $fileName. Use a more specific value.',
        );
      }
      if (action == 'remove') {
        lines.removeAt(matchedIndexes.single);
      } else {
        lines[matchedIndexes.single] = '- $normalizedContent';
      }
    }

    final updated = '${lines.join('\n').trimRight()}\n';
    if (utf8.encode(updated).length > maxMemoryBytes) {
      return AgentMemoryUpdateResult(
        success: false,
        message:
            '$fileName exceeds the 16 KiB limit. Remove or shorten older entries first.',
      );
    }
    await file.writeAsString(updated, flush: true);
    return AgentMemoryUpdateResult(
      success: true,
      message:
          'Updated $fileName. The change will be included in the next model request.',
    );
  }

  static bool containsSensitiveValue(String value) => RegExp(
        r'(?:api[_ -]?key|password|passwd|secret|token|bearer\s+|sk-[A-Za-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)',
        caseSensitive: false,
      ).hasMatch(value);

  String? _explicitPreference(String message) {
    final candidate = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.isEmpty || candidate.length > 240) return null;
    final hasPreferenceSignal = RegExp(
      r'\b(?:i prefer|i like|i love|i want|i do not want|i don\x27t want|always|never|from now on|remember that|prefiero|me gusta|me encanta|quiero que|no quiero|siempre|nunca|recuerda que)\b',
      caseSensitive: false,
    ).hasMatch(candidate);
    final containsSensitiveValue = RegExp(
      r'(?:api[_ -]?key|password|passwd|secret|token|bearer\s+|sk-[A-Za-z0-9_-]{12,}|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\b\d{10,}\b)',
      caseSensitive: false,
    ).hasMatch(candidate);
    if (!hasPreferenceSignal || containsSensitiveValue) return null;
    return candidate;
  }

  Map<String, Object?> _conversationToJson(ChatConversation conversation) => {
        'id': conversation.id,
        'title': conversation.title,
        'projectId': conversation.projectId,
        'projectPath': conversation.projectPath,
        'planMode': conversation.planMode,
        'activeSkillIds': conversation.activeSkillIds,
        'createdAt': _createdAt(conversation).toIso8601String(),
        'contextSummary': conversation.contextSummary,
        'contextSummaryThroughMessageId':
            conversation.contextSummaryThroughMessageId,
        'taskProgress': conversation.taskProgress
            .map((item) => item.toJson())
            .toList(growable: false),
      };

  ChatConversation _conversationFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Conversation ID is missing.');
    }
    return ChatConversation(
      id: id,
      title: json['title'] is String ? json['title'] as String : 'New chat',
      projectId:
          json['projectId'] is String ? json['projectId'] as String : null,
      projectPath:
          json['projectPath'] is String ? json['projectPath'] as String : null,
      planMode: json['planMode'] == true,
      activeSkillIds: (json['activeSkillIds'] as List? ?? const [])
          .whereType<String>()
          .where((value) => value.length <= 120)
          .take(20)
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          _dateFromId(id),
      contextSummary: (json['contextSummary'] is String
              ? json['contextSummary'] as String
              : '')
          .substring(
        0,
        ((json['contextSummary'] is String
                    ? json['contextSummary'] as String
                    : '')
                .length)
            .clamp(0, maxContextSummaryChars)
            .toInt(),
      ),
      contextSummaryThroughMessageId: json['contextSummaryThroughMessageId']
                  is String &&
              (json['contextSummaryThroughMessageId'] as String).length <= 160
          ? json['contextSummaryThroughMessageId'] as String
          : null,
      taskProgress: (json['taskProgress'] as List? ?? const [])
          .map(ChatTaskItem.fromJson)
          .whereType<ChatTaskItem>()
          .take(24)
          .toList(growable: false),
    );
  }

  Map<String, Object?> _messageToJson(ChatMessage message) => {
        'id': message.id,
        'role': message.role.name,
        'content': message.content,
        'status': message.status.name,
        'error': message.error,
        'attachments': [
          for (final attachment in message.attachments)
            {
              'relativePath': attachment.relativePath,
              'content': attachment.content,
              'sizeBytes': attachment.sizeBytes,
            }
        ],
        'toolCalls': [
          for (final call in message.toolCalls)
            {
              'id': call.id,
              'name': call.name,
              'arguments': call.arguments,
              'rawArguments': call.rawArguments,
              'hasValidArguments': call.hasValidArguments,
            }
        ],
        'toolCallId': message.toolCallId,
        'toolName': message.toolName,
        'toolArguments': message.toolArguments,
        'toolActionStatus': message.toolActionStatus?.name,
      };

  ChatMessage _messageFromJson(Map<String, dynamic> json) {
    final role = _enumValue(
      ChatMessageRole.values,
      json['role'],
      ChatMessageRole.assistant,
    );
    var status = _enumValue(
      ChatMessageStatus.values,
      json['status'],
      ChatMessageStatus.complete,
    );
    var actionStatus = _enumValueOrNull(
      ToolActionStatus.values,
      json['toolActionStatus'],
    );
    if (status == ChatMessageStatus.streaming) {
      status = ChatMessageStatus.stopped;
    }
    if (status == ChatMessageStatus.awaitingApproval) {
      status = ChatMessageStatus.complete;
      actionStatus = ToolActionStatus.cancelled;
    }
    final attachments = (json['attachments'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((value) => ChatAttachment(
              relativePath: value['relativePath'] as String? ?? '',
              content: value['content'] as String? ?? '',
              sizeBytes: value['sizeBytes'] as int? ?? 0,
            ))
        .toList(growable: false);
    final toolCalls = (json['toolCalls'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((value) => AgentToolCall(
              id: value['id'] as String? ?? '',
              name: value['name'] as String? ?? '',
              arguments: _stringKeyedMap(value['arguments']),
              rawArguments: value['rawArguments'] as String? ?? '',
              hasValidArguments: value['hasValidArguments'] == true,
            ))
        .toList(growable: false);
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: role,
      content: json['content'] as String? ?? '',
      status: status,
      error: json['error'] as String?,
      attachments: attachments,
      toolCalls: toolCalls,
      toolCallId: json['toolCallId'] as String?,
      toolName: json['toolName'] as String?,
      toolArguments: _stringKeyedMap(json['toolArguments']),
      toolActionStatus: actionStatus,
    );
  }

  T _enumValue<T extends Enum>(List<T> values, Object? value, T fallback) =>
      _enumValueOrNull(values, value) ?? fallback;

  T? _enumValueOrNull<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  Map<String, dynamic> _stringKeyedMap(Object? value) =>
      value is Map<dynamic, dynamic>
          ? value.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};

  DateTime _createdAt(ChatConversation conversation) =>
      conversation.createdAt ?? _dateFromId(conversation.id);

  DateTime _dateFromId(String id) {
    final timestamp = int.tryParse(id.split('-').first);
    if (timestamp == null) return DateTime.now();
    try {
      return DateTime.fromMicrosecondsSinceEpoch(timestamp);
    } on RangeError {
      return DateTime.now();
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _safePathSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return safe.isEmpty
        ? 'chat'
        : safe.substring(0, safe.length.clamp(0, 96).toInt());
  }

  String _lastPathSegment(String path) =>
      path.split(RegExp(r'[\\/]')).where((item) => item.isNotEmpty).last;

  String _normalizeForComparison(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^\s*-\s*'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  Directory _requireRoot() =>
      _root ?? (throw StateError('Agent data store is not initialized.'));

  String _join(List<String> parts) => parts.join(Platform.pathSeparator);
}
