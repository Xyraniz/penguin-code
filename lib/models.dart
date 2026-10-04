enum AppPage { chat, agents, changes, settings }

enum SettingsTab { general, models, tools, shortcuts }

enum ChatMessageRole { user, assistant, tool }

enum ChatMessageStatus {
  streaming,
  complete,
  stopped,
  failed,
  awaitingApproval,
}

enum AgentPermissionMode {
  chatOnly,
  askBeforeEachAction,
  autoApproveProjectReads,
}

enum ToolActionStatus {
  awaitingApproval,
  running,
  completed,
  denied,
  failed,
  cancelled,
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
  const AgentTask({required this.id, required this.prompt});

  final String id;
  final String prompt;
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
  });

  final String id;
  final String title;
  final String projectId;

  ChatConversation copyWith({String? title}) => ChatConversation(
        id: id,
        title: title ?? this.title,
        projectId: projectId,
      );
}
