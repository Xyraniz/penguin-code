import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';

void main() {
  test('keeps the manually configured model available after discovery', () {
    const provider = ProviderProfile(
      id: 'local',
      name: 'Local server',
      model: 'custom-model',
      endpoint: 'http://127.0.0.1:11434/v1',
      onDevice: true,
      models: [ModelProfile(id: 'other-model')],
    );

    expect(
      provider.availableModels.map((model) => model.id),
      ['custom-model', 'other-model'],
    );
  });

  test('uses the discovered display name in the provider route label', () {
    const provider = ProviderProfile(
      id: 'remote',
      name: 'Remote API',
      model: 'model-id',
      endpoint: 'https://api.example.test/v1',
      onDevice: false,
      models: [ModelProfile(id: 'model-id', name: 'Model name')],
    );

    expect(provider.routeLabel, 'Remote API · Model name');
  });

  test('persists subagent continuation context without provider credentials',
      () {
    final task = AgentTask(
      id: 'task-1',
      prompt: 'Review the project',
      status: AgentTaskStatus.stopped,
      parentChatId: 'parent-chat',
      projectId: 'project-1',
      projectPath: r'C:\work\project',
      activeSkillIds: const ['material-3'],
      providerId: 'provider-1',
      providerName: 'Example provider',
      modelId: 'model-1',
      permissionMode: AgentPermissionMode.approveForMe,
      createdAt: DateTime.utc(2026, 10, 5),
      reasoningEffortId: 'medium',
    );

    final restored = AgentTask.fromJson(task.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, task.id);
    expect(restored.parentChatId, task.parentChatId);
    expect(restored.projectPath, task.projectPath);
    expect(restored.activeSkillIds, task.activeSkillIds);
    expect(restored.providerId, task.providerId);
    expect(restored.modelId, task.modelId);
    expect(restored.permissionMode, task.permissionMode);
    expect(restored.reasoningEffortId, task.reasoningEffortId);
    expect(task.toJson().containsKey('apiKey'), isFalse);
  });

  test('ignores malformed optional subagent metadata safely', () {
    final task = AgentTask.fromJson({
      'id': 'task-2',
      'prompt': 'Review the project',
      'createdAt': 12,
      'activeSkillIds': 'invalid',
    });

    expect(task, isNotNull);
    expect(task!.createdAt, isNull);
    expect(task.activeSkillIds, isEmpty);
  });
}
