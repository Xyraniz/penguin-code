import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguin_code/models.dart';
import 'package:penguin_code/penguin_code_app.dart';
import 'package:penguin_code/services/openai_compatible_chat_client.dart';

void main() {
  testWidgets('shows the chat shell and toggles conversation history', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(const PenguinCodeApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose a project to get started'), findsOneWidget);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Subagents'), findsNothing);
    expect(find.text('Changes'), findsNothing);
    expect(find.byKey(const Key('sidebar.panel')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar.toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar.panel')), findsNothing);

    await tester.tap(find.byKey(const Key('sidebar.toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar.panel')), findsOneWidget);
  });

  testWidgets('opens conversation history as a drawer in a compact window', (
    tester,
  ) async {
    await _setDesktopSize(tester, width: 760);
    await tester.pumpWidget(
      const PenguinCodeApp(initialProjects: [_testProject]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar.panel')), findsNothing);
    await tester.tap(find.byKey(const Key('sidebar.toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Recent chats'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar.new-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project.picker.title')), findsOneWidget);
    await tester.tap(find.byKey(const Key('project.select.test-project')));
    await tester.pumpAndSettle();
    expect(find.text('Recent chats'), findsNothing);
    expect(find.text('No messages'), findsOneWidget);
    expect(
      find.text(
        'Project access follows your selected permission. When enabled, the agent can only read supported files inside this folder. It cannot edit files or run commands.',
      ),
      findsOneWidget,
    );
    expect(find.text(r'C:\Projects\penguin-code'), findsOneWidget);
  });

  testWidgets('creates a project from a filesystem root folder', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    const fileSelectorChannel =
        MethodChannel('plugins.flutter.io/file_selector');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      fileSelectorChannel,
      (call) async => '/',
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fileSelectorChannel, null);
    });
    await tester.pumpWidget(const PenguinCodeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home.project.create')));
    await tester.pumpAndSettle();

    expect(find.text('Root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports conversation shortcuts, rename, and search', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(
      const PenguinCodeApp(initialProjects: [_testProject]),
    );
    await tester.pumpAndSettle();

    await _pressShortcut(tester, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project.picker.title')), findsOneWidget);
    await tester.tap(find.byKey(const Key('project.select.test-project')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Options for New chat'), findsOneWidget);

    await _pressShortcut(tester, LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar.panel')), findsNothing);
    await _pressShortcut(tester, LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar.panel')), findsOneWidget);

    await tester.tap(find.byTooltip('Options for New chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat.rename.input')),
      'Security review',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await _pressShortcut(tester, LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat.search.input')),
      'Security',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page.chat')), findsOneWidget);
  });

  testWidgets('adds an in-memory provider profile to the model selector', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(const PenguinCodeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('provider.add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('provider.name')),
      'On-device model',
    );
    await tester.enterText(
      find.byKey(const Key('provider.endpoint')),
      'http://127.0.0.1:11434/v1',
    );
    await tester.enterText(find.byKey(const Key('provider.model')), 'qwen3:8b');
    await tester.enterText(
      find.byKey(const Key('provider.key')),
      'session-only-secret',
    );
    await tester.tap(find.byKey(const Key('provider.save')));
    await tester.pumpAndSettle();

    expect(find.text('On-device model · qwen3:8b'), findsOneWidget);
    expect(
      find.text(
        'Provider profile saved for this session.',
      ),
      findsOneWidget,
    );
    expect(find.text('session-only-secret'), findsNothing);
  });

  testWidgets('sends text and renders a streamed provider reply',
      (tester) async {
    await _setDesktopSize(tester);
    late http.BaseRequest sentRequest;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        sentRequest = request;
        return _chatResponse([
          _sseChunk('Hello'),
          _sseChunk(' from the model.'),
          'data: [DONE]\n\n',
        ].join());
      }),
    );
    await tester.pumpWidget(
      PenguinCodeApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Explain this value',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();

    final messageList = find.byKey(const Key('chat.messages'));
    expect(
      find.descendant(
          of: messageList, matching: find.text('Explain this value')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: messageList,
        matching: find.text('Hello from the model.'),
      ),
      findsOneWidget,
    );
    expect(
        find.text(
            'Connected to Test provider · test-model · selected file context is sent with your message.'),
        findsOneWidget);
    expect((sentRequest as http.Request).headers['authorization'],
        'Bearer session-test-key');
    final body =
        jsonDecode((sentRequest as http.Request).body) as Map<String, dynamic>;
    expect(body['messages'], [
      {'role': 'user', 'content': 'Explain this value'},
    ]);
  });

  testWidgets('attaches selected project code as message context',
      (tester) async {
    await _setDesktopSize(tester);
    late http.BaseRequest sentRequest;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        sentRequest = request;
        return _chatResponse(_sseChunk('I see the selected file.'));
      }),
    );
    await tester.pumpWidget(
      PenguinCodeApp(
        initialProjects: const [_testProject],
        chatClient: client,
        attachmentPicker: (project, alreadyAttached) async {
          expect(project.id, _testProject.id);
          expect(alreadyAttached, isEmpty);
          return const [
            ChatAttachment(
              relativePath: 'lib/example.dart',
              content: 'const answer = 42;',
              sizeBytes: 19,
            ),
          ];
        },
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await _startProjectChat(tester);
    await tester.tap(find.byKey(const Key('composer.attach')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer.attachment.lib/example.dart')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Explain this code',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();

    final body =
        jsonDecode((sentRequest as http.Request).body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>;
    expect(messages, hasLength(1));
    expect(messages.single['content'], contains('lib/example.dart'));
    expect(messages.single['content'], contains('const answer = 42;'));
    expect(messages.single['content'], contains('Explain this code'));
    expect(
      find.descendant(
        of: find.byKey(const Key('chat.messages')),
        matching: find.text('lib/example.dart'),
      ),
      findsOneWidget,
    );
    expect(find.text('const answer = 42;'), findsNothing);
  });

  testWidgets('stops an active response and keeps its partial text',
      (tester) async {
    await _setDesktopSize(tester);
    final stream = StreamController<List<int>>();
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        final abortTrigger = (request as http.AbortableRequest).abortTrigger!;
        abortTrigger.then((_) => stream.close());
        return http.StreamedResponse(stream.stream, 200);
      }),
    );
    await tester.pumpWidget(
      PenguinCodeApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Write a long answer',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pump();
    stream.add(utf8.encode(_sseChunk('Partial answer')));
    await tester.pump();
    expect(find.text('Partial answer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer.stop')));
    await tester.pumpAndSettle();
    expect(find.text('Partial answer'), findsOneWidget);
    expect(find.text('Response stopped'), findsOneWidget);
    await stream.close();
  });

  testWidgets('retries a failed response without duplicating the user turn', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    var requestCount = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return _chatResponse('unauthorized', status: 401);
        }
        return _chatResponse('${_sseChunk('Recovered')}data: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      PenguinCodeApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Try this request again',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 401'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('chat.messages')),
        matching: find.text('Try this request again'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('chat.messages')),
        matching: find.text('Recovered'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('chat.messages')),
        matching: find.text('Try this request again'),
      ),
      findsOneWidget,
    );
    expect(requestCount, 2);
  });

  testWidgets('queues a subagent task preview and opens changes', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(const PenguinCodeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agents.create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agents.task.input')),
      'Review the authentication module',
    );
    await tester.tap(find.byKey(const Key('agents.task.create')));
    await tester.pumpAndSettle();

    expect(find.text('Review the authentication module'), findsOneWidget);
    expect(find.text('Waiting for agent integration'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topbar.changes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page.changes')), findsOneWidget);
    expect(find.text('No pending changes'), findsOneWidget);
  });
}

Future<void> _setDesktopSize(WidgetTester tester, {double width = 1440}) async {
  tester.view.physicalSize = Size(width, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

const _testProject = Project(
  id: 'test-project',
  name: 'Penguin Code',
  path: r'C:\Projects\penguin-code',
);

Future<void> _configureProvider(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sidebar.settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Models'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('provider.add')));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const Key('provider.name')), 'Test provider');
  await tester.enterText(
    find.byKey(const Key('provider.endpoint')),
    'https://provider.example.test/v1',
  );
  await tester.enterText(find.byKey(const Key('provider.model')), 'test-model');
  await tester.enterText(
    find.byKey(const Key('provider.key')),
    'session-test-key',
  );
  await tester.tap(find.byKey(const Key('provider.save')));
  await tester.pumpAndSettle();
}

Future<void> _startProjectChat(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sidebar.new-chat')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('project.select.test-project')));
  await tester.pumpAndSettle();
}

String _sseChunk(String content) => 'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': content}
            }
          ]
        })}\n\n';

http.StreamedResponse _chatResponse(String body, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status);

class _FakeChatClient extends http.BaseClient {
  _FakeChatClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
