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
  });

  final String id;
  final String name;
  final String model;
  final String endpoint;
  final bool onDevice;
  final String? apiKey;

  String get routeLabel => '$name · $model';
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
