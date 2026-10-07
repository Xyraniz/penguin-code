enum AppPage { chat, agents, changes, skills, settings }

enum SettingsTab { general, models, tools, hooks, mcp, memory, shortcuts }

enum ResponseDetail { modelDefault, low, medium, high }

enum ReasoningSummary { automatic, concise, detailed, none }

enum AgentTaskStatus { queued, running, completed, failed, stopped }

enum ChatTaskStatus { pending, inProgress, completed }

enum ChatGoalStatus { active, paused, achieved, impossible }

enum McpTransportType { stdio, http, sse }

enum AgentHookEvent { beforeTool, afterTool, agentFinished }

class AgentHook {
  const AgentHook({
    required this.id,
    required this.name,
    required this.event,
    required this.command,
    this.matcher = '',
    this.enabled = false,
    this.timeoutSeconds = 10,
  });

  final String id;
  final String name;
  final AgentHookEvent event;
  final String command;
  final String matcher;
  final bool enabled;
  final int timeoutSeconds;

  AgentHook copyWith({
    String? name,
    AgentHookEvent? event,
    String? command,
    String? matcher,
    bool? enabled,
    int? timeoutSeconds,
  }) =>
      AgentHook(
        id: id,
        name: name ?? this.name,
        event: event ?? this.event,
        command: command ?? this.command,
        matcher: matcher ?? this.matcher,
        enabled: enabled ?? this.enabled,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      );

  String? get validationError {
    if (id.isEmpty || id.length > 80) return 'The hook ID is invalid.';
    if (name.trim().isEmpty || name.trim().length > 64) {
      return 'Enter a hook name up to 64 characters.';
    }
    if (command.trim().isEmpty || command.length > 4096) {
      return 'Enter a command up to 4 KiB.';
    }
    if (matcher.length > 256) return 'The tool matcher is too long.';
    if (timeoutSeconds < 1 || timeoutSeconds > 60) {
      return 'Hook timeout must be between 1 and 60 seconds.';
    }
    if (matcher.isNotEmpty) {
      try {
        RegExp(matcher);
      } on FormatException {
        return 'The tool matcher is not a valid regular expression.';
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'event': event.name,
        'command': command,
        'matcher': matcher,
        'enabled': enabled,
        'timeoutSeconds': timeoutSeconds,
      };

  static AgentHook? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final event = AgentHookEvent.values
        .where((item) => item.name == value['event'])
        .firstOrNull;
    final command = value['command'];
    final matcher = value['matcher'] ?? '';
    final enabled = value['enabled'] ?? false;
    final timeoutSeconds = value['timeoutSeconds'] ?? 10;
    if (id is! String ||
        name is! String ||
        event == null ||
        command is! String ||
        matcher is! String ||
        enabled is! bool ||
        timeoutSeconds is! int) {
      return null;
    }
    final hook = AgentHook(
      id: id,
      name: name,
      event: event,
      command: command,
      matcher: matcher,
      enabled: enabled,
      timeoutSeconds: timeoutSeconds,
    );
    return hook.validationError == null ? hook : null;
  }
}

class McpServerProfile {
  const McpServerProfile({
    required this.id,
    required this.name,
    this.transport = McpTransportType.stdio,
    this.command = '',
    this.arguments = const [],
    this.endpoint = '',
    this.headers = const {},
    this.savedHeaderNames = const [],
    this.enabled = false,
  });

  final String id;
  final String name;
  final McpTransportType transport;
  final String command;
  final List<String> arguments;
  final String endpoint;

  /// Request headers are loaded from secure storage and are never serialized.
  final Map<String, String> headers;

  /// Header names are safe metadata; values stay in the OS secure store.
  final List<String> savedHeaderNames;
  final bool enabled;

  List<String> get credentialHeaderNames => List.unmodifiable({
        ...savedHeaderNames,
        ...headers.keys,
      });

  McpServerProfile copyWith({
    McpTransportType? transport,
    String? command,
    List<String>? arguments,
    String? endpoint,
    Map<String, String>? headers,
    List<String>? savedHeaderNames,
    bool? enabled,
  }) =>
      McpServerProfile(
        id: id,
        name: name,
        transport: transport ?? this.transport,
        command: command ?? this.command,
        arguments: arguments ?? this.arguments,
        endpoint: endpoint ?? this.endpoint,
        headers: headers ?? this.headers,
        savedHeaderNames: savedHeaderNames ?? this.savedHeaderNames,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.name,
        'command': command,
        'arguments': arguments,
        'endpoint': endpoint,
        'headerNames': credentialHeaderNames,
        'enabled': enabled,
      };

  static McpServerProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final command = value['command'];
    final arguments = value['arguments'];
    final transportName = value['transport'];
    final transport = transportName == null
        ? McpTransportType.stdio
        : McpTransportType.values
            .where((type) => type.name == transportName)
            .firstOrNull;
    final endpoint = value['endpoint'] ?? '';
    final headerNamesValue = value['headerNames'];
    final headerNames = headerNamesValue == null
        ? const <String>[]
        : headerNamesValue is List &&
                headerNamesValue.every((item) => item is String)
            ? List<String>.unmodifiable(headerNamesValue.cast<String>())
            : null;
    final parsedArguments = arguments == null
        ? const <String>[]
        : arguments is List && arguments.every((item) => item is String)
            ? List<String>.unmodifiable(arguments.cast<String>())
            : null;
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        name.trim().length > 80 ||
        transport == null ||
        command != null && command is! String ||
        endpoint is! String ||
        endpoint.length > 2048 ||
        headerNames == null ||
        headerNames.length > 32 ||
        parsedArguments == null) {
      return null;
    }
    final parsedCommand = command is String ? command : '';
    if (transport == McpTransportType.stdio &&
        (parsedCommand.trim().isEmpty ||
            parsedCommand.trim().length > 1024 ||
            parsedCommand.contains('\n') ||
            parsedCommand.contains('\r'))) {
      return null;
    }
    if (transport != McpTransportType.stdio &&
        !isAllowedMcpEndpoint(endpoint)) {
      return null;
    }
    if (headerNames.any((header) => !isValidMcpHeaderName(header))) {
      return null;
    }
    if (parsedArguments.length > 64 ||
        parsedArguments.fold<int>(0, (length, value) => length + value.length) >
            16384) {
      return null;
    }
    return McpServerProfile(
      id: id,
      name: name.trim(),
      transport: transport,
      command: parsedCommand.trim(),
      arguments: parsedArguments,
      endpoint: endpoint.trim(),
      savedHeaderNames: headerNames,
      enabled: value['enabled'] == true,
    );
  }
}

bool isAllowedMcpEndpoint(String value) {
  if (value.isEmpty ||
      value.length > 2048 ||
      value.contains('\n') ||
      value.contains('\r')) {
    return false;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    return false;
  }
  return uri.scheme.toLowerCase() == 'https' || _isLoopbackHost(uri.host);
}

bool isValidMcpHeaderName(String value) =>
    value.length <= 128 &&
    RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(value) &&
    !const {
      'accept',
      'content-length',
      'content-type',
      'host',
      'mcp-protocol-version',
      'mcp-session-id',
    }.contains(value.toLowerCase());

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' ||
      normalized == '::1' ||
      normalized == '[::1]') {
    return true;
  }
  final octets = normalized.split('.');
  if (octets.length != 4) return false;
  final address = octets.map(int.tryParse).toList(growable: false);
  return address.every((octet) => octet != null && octet <= 255) &&
      address.first == 127 &&
      octets.join('.') == address.join('.');
}

enum ChatMessageRole { user, assistant, tool }

enum ChatMessageStatus {
  streaming,
  complete,
  stopped,
  failed,
  awaitingApproval,
}

enum AgentPermissionMode {
  askBeforeEachAction,
  approveForMe,
  fullAccess,
}

enum ToolActionStatus {
  awaitingApproval,
  awaitingPlanReview,
  running,
  completed,
  planApproved,
  planRevisionRequested,
  denied,
  failed,
  cancelled,
  loopBlocked,
}

enum PlanReviewDecision { approve, requestChanges, cancel }

class PlanReviewResponse {
  const PlanReviewResponse({required this.decision, this.feedback = ''});

  final PlanReviewDecision decision;
  final String feedback;
}

class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    required this.rawArguments,
    required this.hasValidArguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String rawArguments;
  final bool hasValidArguments;
}

class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.name,
    required this.model,
    required this.endpoint,
    required this.onDevice,
    this.apiKey,
    this.models = const [],
  });

  final String id;
  final String name;
  final String model;
  final String endpoint;
  final bool onDevice;
  final String? apiKey;
  final List<ModelProfile> models;

  String get routeLabel {
    final selected = availableModels.where((item) => item.id == model);
    final label = selected.isEmpty ? model : selected.first.displayName;
    return '$name · $label';
  }

  List<ModelProfile> get availableModels {
    if (model.isEmpty) return models;
    if (models.any((item) => item.id == model)) return models;
    return [ModelProfile(id: model), ...models];
  }

  ProviderProfile copyWith({String? model, List<ModelProfile>? models}) =>
      ProviderProfile(
        id: id,
        name: name,
        model: model ?? this.model,
        endpoint: endpoint,
        onDevice: onDevice,
        apiKey: apiKey,
        models: models ?? this.models,
      );
}

class ModelProfile {
  const ModelProfile({
    required this.id,
    this.name = '',
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsImages,
    this.supportsTools,
    this.canReason,
    this.reasoningEfforts = const {},
  });

  final String id;
  final String name;
  final int? contextWindow;
  final int? maxOutputTokens;
  final bool? supportsImages;
  final bool? supportsTools;
  final bool? canReason;

  /// Selectable reasoning level -> value sent as `reasoning_effort`.
  /// A null value means the level is represented by omitting that field.
  final Map<String, String?> reasoningEfforts;

  String get displayName => name.isEmpty ? id : name;
}

class ModelReference {
  const ModelReference({required this.providerId, required this.modelId});

  final String providerId;
  final String modelId;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.status,
    this.error,
    this.attachments = const [],
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.toolArguments = const {},
    this.toolActionStatus,
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final ChatMessageStatus status;
  final String? error;
  final List<ChatAttachment> attachments;
  final List<AgentToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final Map<String, dynamic> toolArguments;
  final ToolActionStatus? toolActionStatus;

  ChatMessage copyWith({
    String? content,
    ChatMessageStatus? status,
    String? error,
    List<AgentToolCall>? toolCalls,
    ToolActionStatus? toolActionStatus,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        status: status ?? this.status,
        error: error ?? this.error,
        attachments: attachments,
        toolCalls: toolCalls ?? this.toolCalls,
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolActionStatus: toolActionStatus ?? this.toolActionStatus,
      );
}

class ProjectFileChange {
  const ProjectFileChange({
    required this.projectName,
    required this.chatTitle,
    required this.relativePath,
    required this.oldText,
    required this.newText,
  });

  final String projectName;
  final String chatTitle;
  final String relativePath;
  final String oldText;
  final String newText;
}

class ChatAttachment {
  const ChatAttachment({
    required this.relativePath,
    required this.content,
    required this.sizeBytes,
  });

  final String relativePath;
  final String content;
  final int sizeBytes;
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.prompt,
    this.status = AgentTaskStatus.queued,
    this.result = '',
    this.error,
    this.parentChatId,
    this.projectId,
    this.projectPath,
    this.activeSkillIds = const [],
    this.providerId,
    this.providerName,
    this.modelId,
    this.permissionMode = AgentPermissionMode.askBeforeEachAction,
    this.createdAt,
    this.reasoningEffortId,
  });

  final String id;
  final String prompt;
  final AgentTaskStatus status;
  final String result;
  final String? error;
  final String? parentChatId;
  final String? projectId;
  final String? projectPath;
  final List<String> activeSkillIds;
  final String? providerId;
  final String? providerName;
  final String? modelId;
  final AgentPermissionMode permissionMode;
  final DateTime? createdAt;
  final String? reasoningEffortId;

  Map<String, Object?> toJson() => {
        'id': id,
        'prompt': prompt,
        'status': status.name,
        'result': result,
        'error': error,
        'parentChatId': parentChatId,
        'projectId': projectId,
        'projectPath': projectPath,
        'activeSkillIds': activeSkillIds,
        'providerId': providerId,
        'providerName': providerName,
        'modelId': modelId,
        'permissionMode': permissionMode.name,
        'createdAt': createdAt?.toIso8601String(),
        'reasoningEffortId': reasoningEffortId,
      };

  static AgentTask? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final prompt = value['prompt'];
    if (id is! String || id.trim().isEmpty || id.length > 160) return null;
    if (prompt is! String || prompt.trim().isEmpty || prompt.length > 4096) {
      return null;
    }
    T enumValue<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final item in values) {
        if (item.name == name) return item;
      }
      return fallback;
    }

    AgentPermissionMode permissionModeValue(Object? name) => switch (name) {
          'approveForMe' ||
          'autoApproveProjectReads' =>
            AgentPermissionMode.approveForMe,
          'fullAccess' => AgentPermissionMode.fullAccess,
          _ => AgentPermissionMode.askBeforeEachAction,
        };

    String boundedString(String key, int maxLength, {String fallback = ''}) {
      final candidate = value[key];
      if (candidate is! String) return fallback;
      return candidate.substring(
        0,
        candidate.length.clamp(0, maxLength).toInt(),
      );
    }

    String? optionalString(String key, int maxLength) {
      final candidate = value[key];
      if (candidate is! String) return null;
      return candidate.substring(
        0,
        candidate.length.clamp(0, maxLength).toInt(),
      );
    }

    return AgentTask(
      id: id,
      prompt: prompt,
      status: enumValue(
        AgentTaskStatus.values,
        value['status'],
        AgentTaskStatus.stopped,
      ),
      result: boundedString('result', 12000),
      error: optionalString('error', 4000),
      parentChatId: optionalString('parentChatId', 160),
      projectId: optionalString('projectId', 2048),
      projectPath: optionalString('projectPath', 4096),
      activeSkillIds: (value['activeSkillIds'] is List
              ? value['activeSkillIds'] as List
              : const <Object?>[])
          .whereType<String>()
          .where((item) => item.length <= 120)
          .take(20)
          .toList(growable: false),
      providerId: optionalString('providerId', 160),
      providerName: optionalString('providerName', 120),
      modelId: optionalString('modelId', 300),
      permissionMode: permissionModeValue(value['permissionMode']),
      createdAt: DateTime.tryParse(
        value['createdAt'] is String ? value['createdAt'] as String : '',
      ),
      reasoningEffortId: optionalString('reasoningEffortId', 120),
    );
  }

  AgentTask copyWith({
    AgentTaskStatus? status,
    String? result,
    String? error,
    String? parentChatId,
    String? projectId,
    String? projectPath,
    List<String>? activeSkillIds,
    String? providerId,
    String? providerName,
    String? modelId,
    AgentPermissionMode? permissionMode,
    DateTime? createdAt,
    String? reasoningEffortId,
    bool clearError = false,
  }) =>
      AgentTask(
        id: id,
        prompt: prompt,
        status: status ?? this.status,
        result: result ?? this.result,
        error: clearError ? null : error ?? this.error,
        parentChatId: parentChatId ?? this.parentChatId,
        projectId: projectId ?? this.projectId,
        projectPath: projectPath ?? this.projectPath,
        activeSkillIds: activeSkillIds ?? this.activeSkillIds,
        providerId: providerId ?? this.providerId,
        providerName: providerName ?? this.providerName,
        modelId: modelId ?? this.modelId,
        permissionMode: permissionMode ?? this.permissionMode,
        createdAt: createdAt ?? this.createdAt,
        reasoningEffortId: reasoningEffortId ?? this.reasoningEffortId,
      );
}

class AgentSkillProfile {
  const AgentSkillProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.triggerText,
    required this.isBundled,
    this.directoryPath,
    this.source,
  });

  final String id;
  final String name;
  final String description;
  final String triggerText;
  final bool isBundled;
  final String? directoryPath;
  final String? source;
}

class ChatTaskItem {
  const ChatTaskItem({required this.content, required this.status});

  final String content;
  final ChatTaskStatus status;

  Map<String, Object?> toJson() => {
        'content': content,
        'status': switch (status) {
          ChatTaskStatus.pending => 'pending',
          ChatTaskStatus.inProgress => 'in_progress',
          ChatTaskStatus.completed => 'completed',
        },
      };

  static ChatTaskItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final content = value['content'];
    final status = value['status'];
    if (content is! String || content.trim().isEmpty || content.length > 180) {
      return null;
    }
    final parsedStatus = switch (status) {
      'pending' => ChatTaskStatus.pending,
      'in_progress' => ChatTaskStatus.inProgress,
      'completed' => ChatTaskStatus.completed,
      _ => null,
    };
    if (parsedStatus == null) return null;
    return ChatTaskItem(content: content.trim(), status: parsedStatus);
  }
}

class ChatGoal {
  const ChatGoal({
    required this.objective,
    this.status = ChatGoalStatus.active,
    this.evaluatedTurns = 0,
    this.lastReason = '',
  });

  final String objective;
  final ChatGoalStatus status;
  final int evaluatedTurns;
  final String lastReason;

  ChatGoal copyWith({
    String? objective,
    ChatGoalStatus? status,
    int? evaluatedTurns,
    String? lastReason,
  }) =>
      ChatGoal(
        objective: objective ?? this.objective,
        status: status ?? this.status,
        evaluatedTurns: evaluatedTurns ?? this.evaluatedTurns,
        lastReason: lastReason ?? this.lastReason,
      );

  Map<String, Object?> toJson() => {
        'objective': objective,
        'status': status.name,
        'evaluatedTurns': evaluatedTurns,
        'lastReason': lastReason,
      };

  static ChatGoal? fromJson(Object? value) {
    if (value is! Map) return null;
    final objective = value['objective'];
    if (objective is! String ||
        objective.trim().isEmpty ||
        objective.length > 4000) {
      return null;
    }
    final status = switch (value['status']) {
      'active' => ChatGoalStatus.active,
      'paused' => ChatGoalStatus.paused,
      'achieved' => ChatGoalStatus.achieved,
      'impossible' => ChatGoalStatus.impossible,
      _ => null,
    };
    if (status == null) return null;
    final evaluatedTurns = value['evaluatedTurns'];
    final lastReason = value['lastReason'];
    return ChatGoal(
      objective: objective.trim(),
      status: status,
      evaluatedTurns:
          evaluatedTurns is int ? evaluatedTurns.clamp(0, 10000) : 0,
      lastReason: lastReason is String
          ? lastReason.substring(0, lastReason.length.clamp(0, 1200).toInt())
          : '',
    );
  }
}

class Project {
  const Project({required this.id, required this.name, required this.path});

  final String id;
  final String name;
  final String path;
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.projectId,
    this.planMode = false,
    this.activeSkillIds = const [],
    this.projectPath,
    this.createdAt,
    this.contextSummary = '',
    this.contextSummaryThroughMessageId,
    this.taskProgress = const [],
    this.goal,
  });

  final String id;
  final String title;
  final String? projectId;
  final bool planMode;
  final List<String> activeSkillIds;
  final String? projectPath;
  final DateTime? createdAt;
  final String contextSummary;
  final String? contextSummaryThroughMessageId;
  final List<ChatTaskItem> taskProgress;
  final ChatGoal? goal;

  ChatConversation copyWith({
    String? title,
    bool? planMode,
    List<String>? activeSkillIds,
    String? projectPath,
    String? contextSummary,
    String? contextSummaryThroughMessageId,
    List<ChatTaskItem>? taskProgress,
    ChatGoal? goal,
    bool clearContextSummary = false,
    bool clearGoal = false,
  }) =>
      ChatConversation(
        id: id,
        title: title ?? this.title,
        projectId: projectId,
        planMode: planMode ?? this.planMode,
        activeSkillIds: activeSkillIds ?? this.activeSkillIds,
        projectPath: projectPath ?? this.projectPath,
        createdAt: createdAt,
        contextSummary:
            clearContextSummary ? '' : contextSummary ?? this.contextSummary,
        contextSummaryThroughMessageId: clearContextSummary
            ? null
            : contextSummaryThroughMessageId ??
                this.contextSummaryThroughMessageId,
        taskProgress: taskProgress ?? this.taskProgress,
        goal: clearGoal ? null : goal ?? this.goal,
      );
}
