import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/agent_data_store.dart';

void main() {
  test('migrates legacy memories into the user profile without losing text',
      () async {
    final documents = await Directory.systemTemp.createTemp(
      'penguin-agent-memory-migration-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final root =
        Directory('${documents.path}${Platform.pathSeparator}Penguin-code')
          ..createSync(recursive: true);
    final legacy = File(
      '${root.path}${Platform.pathSeparator}Memories.md',
    )..writeAsStringSync(
        '# Penguin Code memories\n\n## User preferences\n- Keep answers concise.\n',
      );
    final store = AgentDataStore(documentsDirectory: documents);

    await store.initialize();

    expect(await store.readUserProfile(), contains('- Keep answers concise.'));
    expect(await store.readAgentMemory(), contains('## Learned notes'));
    expect(legacy.existsSync(), isFalse);
    expect(store.userProfileFile.existsSync(), isTrue);
    expect(store.agentMemoryFile.existsSync(), isTrue);
  });

  test('keeps user profile and agent notes in separate editable files',
      () async {
    final documents = await Directory.systemTemp.createTemp(
      'penguin-agent-memory-operations-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final store = AgentDataStore(documentsDirectory: documents);
    await store.initialize();

    final userUpdate = await store.applyMemoryOperation(
      action: 'add',
      target: 'user',
      content: 'Prefers short explanations',
    );
    final agentUpdate = await store.applyMemoryOperation(
      action: 'add',
      target: 'memory',
      content: 'The app runs as a Flutter desktop client',
    );

    expect(userUpdate.success, isTrue);
    expect(agentUpdate.success, isTrue);
    expect(
        await store.readUserProfile(), contains('Prefers short explanations'));
    expect(await store.readUserProfile(), isNot(contains('Flutter desktop')));
    expect(await store.readAgentMemory(), contains('Flutter desktop client'));
    expect(await store.readAgentMemory(), isNot(contains('Prefers short')));

    final replacement = await store.applyMemoryOperation(
      action: 'replace',
      target: 'memory',
      oldText: 'Flutter desktop',
      content: 'The app uses native Flutter desktop runners',
    );
    final removal = await store.applyMemoryOperation(
      action: 'remove',
      target: 'user',
      oldText: 'short explanations',
    );
    final secret = await store.applyMemoryOperation(
      action: 'add',
      target: 'memory',
      content: 'Remember this API key: sk-1234567890abcdef',
    );

    expect(replacement.success, isTrue);
    expect(removal.success, isTrue);
    expect(secret.success, isFalse);
    expect(await store.readAgentMemory(), contains('native Flutter desktop'));
    expect(await store.readAgentMemory(),
        isNot(contains('Flutter desktop client')));
    expect(
        await store.readUserProfile(), isNot(contains('short explanations')));
  });

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
      contextSummary: 'The user approved a focused security review.',
      contextSummaryThroughMessageId: 'assistant-1',
      taskProgress: const [
        ChatTaskItem(
          content: 'Inspect the authentication flow',
          status: ChatTaskStatus.completed,
        ),
        ChatTaskItem(
          content: 'Write a concise review',
          status: ChatTaskStatus.inProgress,
        ),
      ],
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
    expect(saved.single.conversation.contextSummary,
        'The user approved a focused security review.');
    expect(saved.single.conversation.contextSummaryThroughMessageId,
        'assistant-1');
    expect(
      saved.single.conversation.taskProgress
          .map((item) => (item.content, item.status))
          .toList(),
      conversation.taskProgress
          .map((item) => (item.content, item.status))
          .toList(),
    );
    expect(saved.single.messages.map((message) => message.content), [
      'Review project security',
      'I found an expired token check.',
    ]);
  });
}
