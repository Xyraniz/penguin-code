import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/agent_data_store.dart';

void main() {
  test('persists resumable subagent task and child conversation together',
      () async {
    final documents = await Directory.systemTemp.createTemp(
      'penguin-agent-data-store-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final store = AgentDataStore(documentsDirectory: documents);
    final createdAt = DateTime.utc(2026, 10, 5, 8);
    final conversation = ChatConversation(
      id: 'child-task-1',
      title: 'Review project security',
      projectId: 'project-1',
      projectPath: r'C:\work\project',
      activeSkillIds: const ['material-3'],
      createdAt: createdAt,
    );
    final task = AgentTask(
      id: conversation.id,
      prompt: 'Review project security',
      status: AgentTaskStatus.stopped,
      result: 'Stopped after the first pass.',
      parentChatId: 'parent-chat-1',
      projectId: conversation.projectId,
      projectPath: conversation.projectPath,
      activeSkillIds: conversation.activeSkillIds,
      providerId: 'provider-1',
      providerName: 'Example API',
      modelId: 'model-1',
      permissionMode: AgentPermissionMode.askBeforeEachAction,
      createdAt: createdAt,
      reasoningEffortId: 'high',
    );
    final messages = [
      const ChatMessage(
        id: 'user-1',
        role: ChatMessageRole.user,
        content: 'Review project security',
        status: ChatMessageStatus.complete,
      ),
      const ChatMessage(
        id: 'assistant-1',
        role: ChatMessageRole.assistant,
        content: 'I found an expired token check.',
        status: ChatMessageStatus.complete,
      ),
    ];

    await store.saveConversation(conversation, messages, agentTask: task);
    final saved = await store.loadConversations();

    expect(saved, hasLength(1));
    expect(saved.single.agentTask?.status, AgentTaskStatus.stopped);
    expect(saved.single.agentTask?.parentChatId, 'parent-chat-1');
    expect(saved.single.agentTask?.permissionMode,
        AgentPermissionMode.askBeforeEachAction);
    expect(saved.single.agentTask?.reasoningEffortId, 'high');
    expect(saved.single.messages.map((message) => message.content), [
      'Review project security',
      'I found an expired token check.',
    ]);
  });
}
