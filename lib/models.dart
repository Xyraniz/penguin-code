enum AppPage { chat, agents, changes, settings }

enum SettingsTab { general, models, tools, shortcuts }

class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.name,
    required this.model,
    required this.endpoint,
    required this.onDevice,
  });

  final String id;
  final String name;
  final String model;
  final String endpoint;
  final bool onDevice;

  String get routeLabel => '$name · $model';
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
