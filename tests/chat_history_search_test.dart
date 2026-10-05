import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/chat_history_search.dart';

void main() {
  final olderChat = ChatConversation(
    id: 'older-chat',
    title: 'Approval policy decision',
    projectId: null,
    createdAt: DateTime(2026, 9, 22),
  );

  test('searches user and assistant text and ranks phrase matches', () {
    final conversations = [olderChat];
    final messages = {
      olderChat.id: [
        const ChatMessage(
          id: 'older-user',
          role: ChatMessageRole.user,
          content:
              'We decided that edits to project files need approval unless full access is enabled.',
          status: ChatMessageStatus.complete,
        ),
        const ChatMessage(
          id: 'older-assistant',
          role: ChatMessageRole.assistant,
          content:
              'Project edits ask for approval unless the user enables full access.',
          status: ChatMessageStatus.complete,
        ),
      ],
    };

    final results = ChatHistorySearch.search(
      conversations: conversations,
      messagesByChatId: messages,
      query: 'what did we decide about project files approval?',
    );

    expect(results, hasLength(2));
    expect(results.first.message?.id, 'older-user');
    expect(results.first.excerpt, contains('edits to project files'));
    expect(results.first.conversation.title, 'Approval policy decision');
  });

  test(
      'excludes tool output, unfinished messages, credentials, and requested ids',
      () {
    final results = ChatHistorySearch.search(
      conversations: [olderChat],
      messagesByChatId: {
        olderChat.id: [
          const ChatMessage(
            id: 'tool-output',
            role: ChatMessageRole.tool,
            content: 'Project file approval details',
            status: ChatMessageStatus.complete,
          ),
          const ChatMessage(
            id: 'unfinished',
            role: ChatMessageRole.user,
            content: 'Project file approval details',
            status: ChatMessageStatus.streaming,
          ),
          const ChatMessage(
            id: 'credential',
            role: ChatMessageRole.assistant,
            content: 'Project file approval uses token=private-value',
            status: ChatMessageStatus.complete,
          ),
          const ChatMessage(
            id: 'current-prompt',
            role: ChatMessageRole.user,
            content: 'Project file approval details',
            status: ChatMessageStatus.complete,
          ),
          const ChatMessage(
            id: 'safe-history',
            role: ChatMessageRole.assistant,
            content:
                'The project file approval mode is Ask before every action.',
            status: ChatMessageStatus.complete,
          ),
        ],
      },
      query: 'project file approval',
      excludedMessageIds: const {'current-prompt'},
    );

    expect(results, hasLength(1));
    expect(results.single.message?.id, 'safe-history');
  });

  test('returns title-only matches for the local conversation picker', () {
    final results = ChatHistorySearch.search(
      conversations: [olderChat],
      messagesByChatId: const {},
      query: 'approval policy',
    );

    expect(results, hasLength(1));
    expect(results.single.message, isNull);
    expect(results.single.excerpt, 'Conversation title match');
  });

  test('bounds query length and result count', () {
    final manyMessages = [
      for (var index = 0; index < 25; index++)
        ChatConversation(
          id: 'chat-$index',
          title: 'File access discussion $index',
          projectId: null,
          createdAt: DateTime(2026, 9, 22).add(Duration(minutes: index)),
        ),
    ];
    final messages = {
      for (final chat in manyMessages)
        chat.id: [
          ChatMessage(
            id: 'message-${chat.id}',
            role: ChatMessageRole.user,
            content: 'We discussed project file access rules.',
            status: ChatMessageStatus.complete,
          ),
        ],
    };

    expect(
      ChatHistorySearch.search(
        conversations: manyMessages,
        messagesByChatId: messages,
        query: 'x' * (ChatHistorySearch.maxQueryCharacters + 1),
      ),
      isEmpty,
    );
    expect(
      ChatHistorySearch.search(
        conversations: manyMessages,
        messagesByChatId: messages,
        query: 'project file access',
        limit: 999,
      ),
      hasLength(ChatHistorySearch.maxResults),
    );
  });
}
