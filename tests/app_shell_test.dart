import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguin_code/models.dart';
import 'package:penguin_code/penguin_code_app.dart';
import 'package:penguin_code/services/agent_data_store.dart';
import 'package:penguin_code/services/openai_compatible_chat_client.dart';
import 'package:penguin_code/services/mcp_stdio_client.dart';
import 'package:penguin_code/services/mcp_credential_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

late AgentDataStore _testDataStore;

void main() {
  late Directory testDocumentsDirectory;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  setUp(() async {
    testDocumentsDirectory =
        await Directory.systemTemp.createTemp('penguin-app-shell-documents-');
    _testDataStore = AgentDataStore(documentsDirectory: testDocumentsDirectory);
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      if (testDocumentsDirectory.existsSync()) {
        for (var attempt = 0; attempt < 20; attempt++) {
          try {
            await testDocumentsDirectory.delete(recursive: true);
            break;
          } on FileSystemException {
            if (attempt == 19) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    });
  });

  testWidgets('shows the chat shell and toggles conversation history', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose a folder to add a project.'), findsOneWidget);
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

  testWidgets('configures hooks and checkpoints from Settings', (tester) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.tab.hooks')));
    await tester.pumpAndSettle();

    final checkpointsToggle =
        find.byKey(const Key('settings.checkpoints.enabled'));
    final hooksToggle = find.byKey(const Key('settings.hooks.enabled'));
    expect(tester.widget<Switch>(checkpointsToggle).value, isFalse);
    expect(tester.widget<Switch>(hooksToggle).value, isFalse);
    await tester.tap(checkpointsToggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.hooks.add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings.hooks.name')),
      'Block unsafe commands',
    );
    await tester.enterText(
      find.byKey(const Key('settings.hooks.command')),
      "Write-Output 'Checked'",
    );
    await tester.tap(find.byKey(const Key('settings.hooks.save')));
    await tester.pumpAndSettle();
    final hookToggle = find.byWidgetPredicate((widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>)
            .value
            .startsWith('settings.hook.enabled.'));
    expect(hookToggle, findsOneWidget);
    await tester.ensureVisible(hookToggle);
    await tester.pumpAndSettle();
    await tester.tap(hookToggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(hooksToggle);
    await tester.pumpAndSettle();
    await tester.tap(hooksToggle);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    final preferences = SharedPreferencesAsync();
    expect(
      await tester.runAsync(
        () => preferences.getBool('penguin_code.checkpoints_enabled'),
      ),
      isTrue,
    );
    expect(
      await tester.runAsync(
        () => preferences.getBool('penguin_code.hooks_enabled'),
      ),
      isTrue,
    );
    final savedHooks = await tester.runAsync(
      () => preferences.getString('penguin_code.agent_hooks'),
    );
    expect(savedHooks, contains('Block unsafe commands'));
    expect(savedHooks, contains('"enabled":true'));
  });

  testWidgets('ignores malformed saved hooks without resetting other settings',
      (tester) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString('penguin_code.agent_hooks', '{');
    await preferences.setString('penguin_code.response_detail', 'high');
    await _setDesktopSize(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButtonFormField<ResponseDetail>>(
            find.byKey(const Key('settings.responseDetail')),
          )
          .initialValue,
      ResponseDetail.high,
    );
  });

  testWidgets('keeps skill learning opt-in and requires review to install', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final response = responseIndex++ == 0
            ? _sseToolCall(
                name: 'propose_skill_change',
                id: 'propose-review-skill',
                arguments: jsonEncode({
                  'action': 'create',
                  'name': 'Review checklist',
                  'description':
                      'Review implementation changes before delivery.',
                  'procedure':
                      'Read the changed code. Run relevant checks. Report concrete findings and unresolved risks.',
                }),
              )
            : _sseChunk('I drafted a reusable skill for review.');
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(_testApp(chatClient: client));
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memories'));
    await tester.pumpAndSettle();
    final skillLearningToggle = find.byKey(
      const Key('settings.memories.skillLearning'),
    );
    await tester.ensureVisible(skillLearningToggle);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(skillLearningToggle).value, isFalse);
    expect(
      tester.widget<SwitchListTile>(skillLearningToggle).onChanged,
      isNotNull,
    );

    await tester.tap(skillLearningToggle);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(tester.widget<SwitchListTile>(skillLearningToggle).value, isTrue);
    expect(
      await tester.runAsync(
        () => SharedPreferencesAsync().getBool(
          'penguin_code.skill_learning_enabled',
        ),
      ),
      isTrue,
    );

    await _createNewChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Please capture the reusable review process from this task.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    for (var attempt = 0; attempt < 80 && requests.length < 2; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(
      requests,
      hasLength(2),
      reason:
          'visible text: ${find.byType(Text).evaluate().map((element) => (element.widget as Text).data).toList()}',
    );

    final toolNames = (requests.first['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(toolNames, contains('propose_skill_change'));
    final toolResult = (requests[1]['messages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .lastWhere((message) => message['role'] == 'tool');
    expect(toolResult['content'], contains('waiting for review in Skills'));

    await tester.tap(find.byKey(const Key('sidebar.skills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skills.pendingProposals')), findsOneWidget);
    final reviewButton = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('skills.pending.review.');
    });
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skills.pending.proposedContent')),
        findsOneWidget);
    final approveButton = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('skills.pending.approve.');
    });
    await tester.tap(approveButton);
    for (var attempt = 0;
        attempt < 80 && approveButton.evaluate().isNotEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }

    final installedSkill = File(
      '${testDocumentsDirectory.path}${Platform.pathSeparator}Penguin-code'
      '${Platform.pathSeparator}Skills${Platform.pathSeparator}review-checklist'
      '${Platform.pathSeparator}SKILL.md',
    );
    expect(await tester.runAsync(installedSkill.exists), isTrue);
    expect(await tester.runAsync(installedSkill.readAsString),
        contains('Report concrete findings'));
    expect(find.byKey(const Key('skills.pendingProposals')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens conversation history as a drawer in a compact window', (
    tester,
  ) async {
    await _setDesktopSize(tester, width: 760);
    await tester.pumpWidget(
      _testApp(initialProjects: [_testProject]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar.panel')), findsNothing);
    await tester.tap(find.byKey(const Key('sidebar.toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Recent chats'), findsOneWidget);

    await _createNewChat(tester);
    expect(find.byKey(const Key('project.picker.title')), findsNothing);
    await tester.tap(find.byKey(const Key('composer.project.select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.select.test-project')));
    await tester.pumpAndSettle();
    await _createNewChat(tester);
    expect(find.text('Recent chats'), findsNothing);
    expect(find.text('No messages'), findsOneWidget);
    expect(
      find.text(
        'Every file action and connected tool call needs your approval. Commands require Full access.',
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
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar.project.create')));
    await tester.pumpAndSettle();

    expect(find.text('Root'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requires confirmation before enabling full access', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(
      _testApp(initialProjects: [_testProject]),
    );
    await tester.pumpAndSettle();
    await _startProjectChat(tester);

    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.fullAccess')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('project.access.confirm.dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('project.access.confirm.cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Computer access: Ask first.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.fullAccess')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.access.confirm.enable')));
    await tester.pumpAndSettle();
    expect(
      find.text('Full access is on · files and commands run without approval.'),
      findsOneWidget,
    );
  });

  testWidgets('runs a command after full access is confirmed', (tester) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-full-access-ui-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    final project = Project(
      id: 'full-access-project',
      name: 'Full access project',
      path: projectDirectory.path,
    );
    final source = File(
      '${projectDirectory.path}${Platform.pathSeparator}main.dart',
    );
    await tester.runAsync(
      () => source.writeAsString('const greeting = "Hello";\n'),
    );
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final command = Platform.isWindows
        ? "Write-Output 'penguin-ui-command-ok'"
        : "printf 'penguin-ui-command-ok'";
    final editArguments = jsonEncode({
      'file_path': 'main.dart',
      'old_string': 'Hello',
      'new_string': 'Penguin',
    });
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final body = switch (responseIndex++) {
          0 => _sseToolCall(
              name: 'read_project_file',
              arguments: '{"path":"main.dart"}',
              id: 'full-access-read',
            ),
          1 => _sseToolCall(
              name: 'edit_project_file',
              arguments: editArguments,
              id: 'full-access-edit',
            ),
          2 => _sseToolCall(
              name: 'run_command',
              arguments: jsonEncode({'command': command}),
              id: 'full-access-command',
            ),
          _ => _sseChunk('The command returned successfully.'),
        };
        return _chatResponse('$body\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: [project],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);

    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.fullAccess')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.access.confirm.enable')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Run the project verification command',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    for (var attempt = 0; attempt < 300 && responseIndex < 4; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(responseIndex, 4, reason: 'The command response should complete.');
    final commandToolResults = requests[3]['messages'] as List<dynamic>;
    expect(
      commandToolResults.any(
        (message) =>
            message is Map<String, dynamic> &&
            message['role'] == 'tool' &&
            '${message['content']}'.contains('Command completed successfully.'),
      ),
      isTrue,
      reason: 'The model should receive the completed command result.',
    );
    await _pumpUntilVisible(
      tester,
      find.text('The command returned successfully.'),
    );

    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Penguin";\n',
    );
    expect(
      find.textContaining('stdout:\npenguin-ui-command-ok'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('chat.tool.approve.full-access-edit')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('chat.tool.approve.full-access-command')),
      findsNothing,
    );
  });

  testWidgets('runs independent auto-approved reads and keeps result order', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-parallel-reads-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    await tester.runAsync(() async {
      await File('${projectDirectory.path}/alpha.txt')
          .writeAsString('first file');
      await File('${projectDirectory.path}/beta.txt')
          .writeAsString('needle in second file');
    });
    final project = Project(
      id: 'parallel-read-project',
      name: 'Parallel read project',
      path: projectDirectory.path,
    );
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final body = responseIndex++ == 0
            ? _sseToolCalls([
                {
                  'id': 'parallel-list',
                  'name': 'list_project_files',
                  'arguments': '{}',
                },
                {
                  'id': 'parallel-read',
                  'name': 'read_project_file',
                  'arguments': '{"path":"alpha.txt"}',
                },
                {
                  'id': 'parallel-search',
                  'name': 'search_project_files',
                  'arguments': '{"query":"needle"}',
                },
              ])
            : _sseChunk('Parallel reads finished.');
        return _chatResponse('$body\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(initialProjects: [project], chatClient: client),
    );
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);
    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.approveForMe')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Read these project files.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    for (var attempt = 0;
        attempt < 80 && find.text('Completed').evaluate().length < 3;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.text('Completed'), findsNWidgets(3));

    expect(requests, hasLength(2));
    final results = (requests[1]['messages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where((message) => message['role'] == 'tool')
        .toList();
    expect(results, hasLength(3));
    expect(results.map((message) => message['tool_call_id']), [
      'parallel-list',
      'parallel-read',
      'parallel-search',
    ]);
    expect(results[0]['content'], contains('alpha.txt'));
    expect(results[1]['content'], contains('first file'));
    expect(results[2]['content'], contains('beta.txt'));
  });

  testWidgets(
    'stops the fifth identical full access call and resets next turn',
    (tester) async {
      await _setDesktopSize(tester);
      final projectDirectory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('penguin-loop-guard-ui-'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
      );
      final project = Project(
        id: 'loop-guard-project',
        name: 'Loop guard project',
        path: projectDirectory.path,
      );
      final source = File(
        '${projectDirectory.path}${Platform.pathSeparator}main.dart',
      );
      await tester.runAsync(
        () => source.writeAsString('const greeting = "Hello";\n'),
      );
      final arguments = jsonEncode({'path': 'main.dart'});
      final requests = <Map<String, dynamic>>[];
      var responseIndex = 0;
      final client = OpenAiCompatibleChatClient(
        client: _FakeChatClient((request) async {
          final index = responseIndex++;
          requests.add(
            jsonDecode((request as http.Request).body) as Map<String, dynamic>,
          );
          final body = index <= 4 || index == 6
              ? _sseToolCall(
                  name: 'read_project_file',
                  arguments: arguments,
                  id: 'repeat-$index',
                )
              : _sseChunk(
                  index == 5
                      ? 'I changed approach after the repeated call was stopped.'
                      : 'The new request ran successfully.',
                );
          return _chatResponse('$body\ndata: [DONE]\n\n');
        }),
      );
      await tester.pumpWidget(
        _testApp(
          initialProjects: [project],
          chatClient: client,
        ),
      );
      await tester.pumpAndSettle();
      await _configureProvider(tester);
      await _startProjectChatFor(tester, project.id);
      await tester.tap(find.byKey(const Key('project.access.menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('project.access.option.fullAccess')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project.access.confirm.enable')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('composer.input')),
        'Read the same file repeatedly',
      );
      await tester.tap(find.byKey(const Key('composer.send')));
      for (var attempt = 0; attempt < 80 && responseIndex < 6; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        responseIndex,
        6,
        reason: 'The tool loop should complete its turn.',
      );
      await _pumpUntilVisible(
        tester,
        find.text('I changed approach after the repeated call was stopped.'),
      );

      expect(responseIndex, 6);
      expect(find.text('Loop stopped'), findsOneWidget);
      final requestBeforeBlockedCall = requests[4]['messages'] as List<dynamic>;
      expect(
        requestBeforeBlockedCall.where(
          (message) =>
              message is Map<String, dynamic> && message['role'] == 'tool',
        ),
        hasLength(4),
      );
      final messagesAfterBlockedCall = requests[5]['messages'] as List<dynamic>;
      expect(
        messagesAfterBlockedCall.any(
          (message) =>
              message is Map<String, dynamic> &&
              message['role'] == 'tool' &&
              '${message['content']}'.contains(
                'Repeated tool call stopped before execution',
              ),
        ),
        isTrue,
      );

      await tester.enterText(
        find.byKey(const Key('composer.input')),
        'Run it once more in this new request',
      );
      await tester.tap(find.byKey(const Key('composer.send')));
      await _pumpUntilVisible(
        tester,
        find.text('The new request ran successfully.'),
      );
      final messagesAfterNewCall = requests[7]['messages'] as List<dynamic>;
      expect(
        messagesAfterNewCall.any(
          (message) =>
              message is Map<String, dynamic> &&
              message['role'] == 'tool' &&
              '${message['content']}'.contains('const greeting = "Hello";'),
        ),
        isTrue,
      );
    },
  );

  testWidgets('reviews a plan before enabling project edits', (tester) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-plan-mode-ui-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    final source = File(
      '${projectDirectory.path}${Platform.pathSeparator}main.dart',
    );
    await tester.runAsync(
      () => source.writeAsString('const greeting = "Hello";\n'),
    );
    final project = Project(
      id: 'plan-project',
      name: 'Plan project',
      path: projectDirectory.path,
    );
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final response = switch (responseIndex++) {
          0 => _sseToolCall(
              name: 'read_project_file',
              arguments: '{"path":"main.dart"}',
              id: 'plan-read',
            ),
          1 => _sseToolCall(
              name: 'submit_plan',
              arguments: jsonEncode({
                'plan': '# Update greeting\n\n1. Change the greeting.\n',
              }),
              id: 'plan-first',
            ),
          2 => _sseToolCall(
              name: 'submit_plan',
              arguments: jsonEncode({
                'plan':
                    '# Update greeting and docs\n\n1. Change the greeting.\n2. Update the README.\n',
              }),
              id: 'plan-second',
            ),
          3 => _sseToolCall(
              name: 'edit_project_file',
              arguments: jsonEncode({
                'file_path': 'main.dart',
                'old_string': 'Hello',
                'new_string': 'Penguin',
              }),
              id: 'edit-after-plan',
            ),
          _ => _sseChunk('Implementation finished.'),
        };
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(initialProjects: [project], chatClient: client),
    );
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);

    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('project.access.option.approveForMe'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer.plan.toggle')));
    await tester.pumpAndSettle();
    expect(
      find.text('Plan first is on · read-only until approval.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Update the greeting and document the change.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat.plan.revise.plan-first')),
    );
    await tester.pumpAndSettle();

    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );
    final firstPlanTools = (requests[0]['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(firstPlanTools, contains('submit_plan'));
    expect(firstPlanTools, isNot(contains('edit_project_file')));
    expect(firstPlanTools, isNot(contains('run_command')));

    final reviseButton = find.byKey(const Key('chat.plan.revise.plan-first'));
    await tester.ensureVisible(reviseButton);
    await tester.tap(reviseButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat.plan.feedback')),
      'Include a short README update in the plan.',
    );
    await tester.tap(find.byKey(const Key('chat.plan.feedback.submit')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat.plan.approve.plan-second')),
    );
    await tester.pumpAndSettle();
    expect(
      (requests[2]['messages'] as List<dynamic>).any(
        (message) =>
            message is Map<String, dynamic> &&
            message['role'] == 'tool' &&
            '${message['content']}'.contains(
              'Include a short README update in the plan.',
            ),
      ),
      isTrue,
    );
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );

    final approvePlanButton =
        find.byKey(const Key('chat.plan.approve.plan-second'));
    await tester.ensureVisible(approvePlanButton);
    await tester.tap(approvePlanButton);
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat.tool.approve.edit-after-plan')),
    );
    await tester.pumpAndSettle();
    final executionTools = (requests[3]['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(executionTools, contains('edit_project_file'));
    expect(executionTools, isNot(contains('submit_plan')));
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );

    final approveEditButton =
        find.byKey(const Key('chat.tool.approve.edit-after-plan'));
    await tester.ensureVisible(approveEditButton);
    await tester.tap(approveEditButton);
    await _pumpUntilVisible(tester, find.text('Implementation finished.'));
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Penguin";\n',
    );
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('cancelling plan review leaves project files untouched', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-plan-cancel-ui-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    final source = File(
      '${projectDirectory.path}${Platform.pathSeparator}main.dart',
    );
    await tester.runAsync(
      () => source.writeAsString('const greeting = "Hello";\n'),
    );
    final project = Project(
      id: 'cancel-plan-project',
      name: 'Cancel plan project',
      path: projectDirectory.path,
    );
    var requestCount = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requestCount++;
        return _chatResponse(
          '${_sseToolCall(
            name: 'submit_plan',
            arguments:
                jsonEncode({'plan': '# Change greeting\n\n1. Edit main.dart.'}),
            id: 'cancel-plan',
          )}data: [DONE]\n\n',
        );
      }),
    );
    await tester.pumpWidget(
      _testApp(initialProjects: [project], chatClient: client),
    );
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);
    await tester.tap(find.byKey(const Key('composer.plan.toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Plan a safe greeting update.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    final cancelPlanButton =
        find.byKey(const Key('chat.plan.cancel.cancel-plan'));
    await _pumpUntilVisible(tester, cancelPlanButton);
    await tester.pumpAndSettle();
    await tester.ensureVisible(cancelPlanButton);
    await tester.tap(cancelPlanButton);
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.text('Cancelled'), findsOneWidget);
    final planChip = tester.widget<FilterChip>(
      find.byKey(const Key('composer.plan.toggle')),
    );
    expect(planChip.selected, isFalse);
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );
  });

  testWidgets('blocks an unexpected edit call while Plan first is active', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-plan-guard-ui-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    final outsideDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-plan-outside-ui-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => outsideDirectory.delete(recursive: true)),
    );
    final source = File.fromUri(
      Directory(projectDirectory.path).uri.resolve('main.dart'),
    );
    final outsideFile = File.fromUri(
      Directory(outsideDirectory.path).uri.resolve('private.txt'),
    );
    await tester.runAsync(
      () => source.writeAsString('const greeting = "Hello";\n'),
    );
    await tester.runAsync(
      () => outsideFile.writeAsString('private computer data'),
    );
    final project = Project(
      id: 'plan-guard-project',
      name: 'Plan guard project',
      path: projectDirectory.path,
    );
    var responseIndex = 0;
    final requests = <Map<String, dynamic>>[];
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final response = switch (responseIndex++) {
          0 => _sseToolCall(
              name: 'read_project_file',
              arguments: jsonEncode({'path': outsideFile.path}),
              id: 'plan-outside-read',
            ),
          1 => _sseToolCall(
              name: 'edit_project_file',
              arguments: jsonEncode({
                'file_path': 'main.dart',
                'old_string': 'Hello',
                'new_string': 'Unexpected',
              }),
              id: 'plan-guard-edit',
            ),
          _ => _sseChunk('I will wait for plan approval before editing.'),
        };
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(initialProjects: [project], chatClient: client),
    );
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);
    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.fullAccess')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.access.confirm.enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer.plan.toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Review the project before changing anything.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.textContaining(
          'This action is unavailable while Plan first is active.'),
    );

    final planTools = (requests.first['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(planTools, isNot(contains('edit_project_file')));
    expect(planTools, isNot(contains('run_command')));
    final secondRequestMessages = requests[1]['messages'] as List<dynamic>;
    expect(
      secondRequestMessages.any(
        (message) =>
            message is Map<String, dynamic> &&
            message['role'] == 'tool' &&
            message['content']
                .toString()
                .contains('Use a path relative to the selected project.'),
      ),
      isTrue,
    );
    expect(
      secondRequestMessages.any(
        (message) =>
            message is Map<String, dynamic> &&
            message['content'].toString().contains('private computer data'),
      ),
      isFalse,
    );
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );
    expect(responseIndex, 3);
    await _pumpUntilVisible(
      tester,
      find.text('I will wait for plan approval before editing.'),
    );
  });

  testWidgets('supports conversation shortcuts, rename, and search', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(
      _testApp(initialProjects: [_testProject]),
    );
    await tester.pumpAndSettle();

    await _pressShortcut(tester, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project.picker.title')), findsNothing);
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
    await tester.pumpWidget(
      _testApp(
        chatClient: OpenAiCompatibleChatClient(
          client: _FakeChatClient((_) async => _chatResponse('')),
        ),
      ),
    );
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

  testWidgets('MCP calls still require approval in Full access mode', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final mcpTransport = _AppFakeMcpTransport();
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final body = responseIndex++ == 0
            ? _sseToolCall(
                name: 'mcp_tool_00_lookup',
                arguments: '{"query":"penguin"}',
                id: 'mcp-call',
              )
            : _sseChunk('The MCP lookup completed.');
        return _chatResponse('$body\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(_testApp(
      initialProjects: const [_testProject],
      chatClient: client,
      mcpTransportFactory: (_) async => mcpTransport,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MCP servers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.mcp.add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('settings.mcp.name')), 'Test MCP');
    await tester.enterText(
        find.byKey(const Key('settings.mcp.command')), 'fake-mcp');
    await tester.tap(find.byKey(const Key('settings.mcp.add.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Connected · 1 tool'), findsOneWidget);

    await tester.tap(find.text('Tools and permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.fullAccess')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.access.confirm.enable')));
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await tester.tap(find.byKey(const Key('sidebar.new-chat')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Look up penguin information',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat.tool.approve.mcp-call')),
    );

    final exposedTools = (requests.first['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(exposedTools, contains('mcp_tool_00_lookup'));
    expect(mcpTransport.toolCalls, isEmpty);

    await tester.tap(find.byKey(const Key('chat.tool.approve.mcp-call')));
    await _pumpUntilVisible(tester, find.text('The MCP lookup completed.'));
    expect(mcpTransport.toolCalls, [
      {
        'name': 'lookup',
        'arguments': {'query': 'penguin'}
      },
    ]);
    expect(find.textContaining('MCP tool · lookup'), findsOneWidget);
  });

  testWidgets('remote MCP settings store authorization headers securely', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final credentials = _RecordingMcpCredentialStore();
    await tester.pumpWidget(_testApp(mcpCredentialStore: credentials));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MCP servers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.mcp.add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings.mcp.name')),
      'Remote tools',
    );
    await tester.tap(find.byKey(const Key('settings.mcp.transport')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTP (Streamable HTTP)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings.mcp.endpoint')),
      'https://mcp.example.test/mcp',
    );
    await tester.enterText(
      find.byKey(const Key('settings.mcp.headers')),
      'Authorization: Bearer private-test-token',
    );
    await tester.tap(find.byKey(const Key('settings.mcp.add.save')));
    await tester.pumpAndSettle();

    expect(find.text('https://mcp.example.test/mcp'), findsOneWidget);
    expect(credentials.savedHeaders, hasLength(1));
    expect(credentials.savedHeaders.values.single, {
      'Authorization': 'Bearer private-test-token',
    });
    expect(find.text('Bearer private-test-token'), findsNothing);
  });

  testWidgets('memory tool stores agent notes separately in ask approval mode',
      (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        final body =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        requests.add(body);
        final response = switch (responseIndex++) {
          0 => _sseToolCall(
              name: 'memory',
              arguments: jsonEncode({
                'action': 'add',
                'target': 'memory',
                'content': 'The chat app uses Flutter desktop runners',
              }),
              id: 'memory-add',
            ),
          1 => _sseChunk('I saved that durable note.'),
          _ => _sseChunk('I remember the app architecture.'),
        };
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(_testApp(chatClient: client));
    await tester.pumpAndSettle();
    await _configureProvider(tester);

    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memories'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('settings.memories.user.editor')), findsOneWidget);
    expect(find.byKey(const Key('settings.memories.agent.editor')),
        findsOneWidget);
    await tester.tap(find.text('Tools and permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.askBeforeEachAction')),
    );
    await tester.pumpAndSettle();

    await _createNewChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Remember a durable note about the app architecture.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    for (var attempt = 0; attempt < 40 && requests.isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(requests, hasLength(1));
    expect(
      (requests.first['tools'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((tool) => (tool['function'] as Map<String, dynamic>)['name']),
      containsAll(['memory', 'update_task_progress']),
    );
    for (var attempt = 0; attempt < 40 && responseIndex < 2; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(responseIndex, 2, reason: 'The memory tool turn should complete.');
    await _pumpUntilVisible(tester, find.text('I saved that durable note.'));

    expect(await tester.runAsync(_testDataStore.readAgentMemory),
        contains('Flutter desktop runners'));
    expect(await tester.runAsync(_testDataStore.readUserProfile),
        isNot(contains('Flutter desktop runners')));

    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'What do you remember about the app?',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text('I remember the app architecture.'),
    );
    final nextTurnInstructions = ((requests.last['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((message) => message['role'] == 'system')
        .map((message) => message['content'] as String)).join('\n');
    expect(nextTurnInstructions, contains('Agent notes from MEMORY.md'));
    expect(nextTurnInstructions, contains('Flutter desktop runners'));
  });

  testWidgets('searches past chats locally and exposes an opt-in read tool', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final previousChat = ChatConversation(
      id: 'history-approval-chat',
      title: 'Approval policy decision',
      projectId: null,
      createdAt: DateTime(2026, 9, 22),
    );
    final previousMessages = [
      const ChatMessage(
        id: 'history-approval-user',
        role: ChatMessageRole.user,
        content:
            'We decided that edits to project files need approval unless full access is enabled.',
        status: ChatMessageStatus.complete,
      ),
      const ChatMessage(
        id: 'history-approval-tool',
        role: ChatMessageRole.tool,
        content: 'Tool output should never appear in search results.',
        status: ChatMessageStatus.complete,
      ),
    ];
    await tester.runAsync(
      () => _testDataStore.saveConversation(previousChat, previousMessages),
    );
    expect(
        await tester.runAsync(_testDataStore.loadConversations), hasLength(1));

    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        final body =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        requests.add(body);
        final response = switch (responseIndex++) {
          0 => _sseChunk('Past chat search is off by default.'),
          1 => _sseToolCall(
              name: 'search_past_chats',
              arguments: jsonEncode({
                'query': 'project files approval',
                'limit': 4,
              }),
              id: 'search-prior-approval',
            ),
          _ => _sseChunk('I found the earlier approval decision.'),
        };
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );

    await tester.pumpWidget(_testApp(chatClient: client));
    await tester.pumpAndSettle();
    await _pumpUntilVisible(tester, find.text('Approval policy decision'));

    await _pressShortcut(tester, LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat.search.input')),
      'project files approval',
    );
    await tester.pumpAndSettle();
    final searchResult = find.byKey(
      const Key(
          'chat.search.result.history-approval-chat.history-approval-user'),
    );
    expect(searchResult, findsOneWidget);
    expect(
      find.textContaining('edits to project files need approval'),
      findsOneWidget,
    );
    await tester.tap(searchResult);
    await tester.pumpAndSettle();
    expect(find.text('Approval policy decision'), findsOneWidget);

    await _configureProvider(tester);
    await _createNewChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Give me one short greeting.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text('Past chat search is off by default.'),
    );
    List<String> toolNames(Map<String, dynamic> body) =>
        (body['tools'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((tool) =>
                (tool['function'] as Map<String, dynamic>)['name'] as String)
            .toList();

    expect(toolNames(requests.first), contains('memory'));
    expect(toolNames(requests.first), isNot(contains('search_past_chats')));

    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memories'));
    await tester.pumpAndSettle();
    final searchToggle = find.byKey(
      const Key('settings.historySearch.enabled'),
    );
    expect(tester.widget<SwitchListTile>(searchToggle).value, isFalse);
    await tester.ensureVisible(searchToggle);
    await tester.pumpAndSettle();
    await tester.tap(searchToggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(searchToggle).value, isTrue);

    await _createNewChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'What did we decide about project file approvals?',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text('I found the earlier approval decision.'),
    );

    expect(
        toolNames(requests[1]), containsAll(['memory', 'search_past_chats']));
    final toolResults = (requests[2]['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((message) => message['role'] == 'tool')
        .map((message) => message['content'].toString())
        .join('\n');
    expect(toolResults, contains('Approval policy decision'));
    expect(toolResults, contains('edits to project files need approval'));
    expect(toolResults, isNot(contains('Tool output should never appear')));
  });

  testWidgets('tracks multi-step progress through provider requests', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        final body =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        requests.add(body);
        final response = responseIndex++ == 0
            ? _sseToolCall(
                name: 'update_task_progress',
                arguments: jsonEncode({
                  'todos': [
                    {'content': 'Inspect the project', 'status': 'completed'},
                    {
                      'content': 'Implement the requested change',
                      'status': 'in_progress'
                    },
                    {'content': 'Run the test suite', 'status': 'pending'},
                  ],
                }),
                id: 'record-task-progress',
              )
            : _sseChunk('I am working through the checklist.');
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(_testApp(chatClient: client));
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _createNewChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Implement this multi-step change and run tests.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
        tester, find.text('I am working through the checklist.'));

    final toolNames = (requests.first['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(toolNames, contains('update_task_progress'));
    expect(find.byKey(const Key('chat.task-progress')), findsOneWidget);
    expect(find.text('1 of 3 completed'), findsOneWidget);
    expect(find.text('Implement the requested change'), findsOneWidget);

    final toolResult = (requests[1]['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .lastWhere((message) => message['role'] == 'tool');
    expect(toolResult['content'], 'Updated task progress: 1 of 3 completed.');
    final followUpMessages =
        (requests[1]['messages'] as List<dynamic>).cast<Map<String, dynamic>>();
    final systemContext = followUpMessages
        .where((message) => message['role'] == 'system')
        .map((message) => message['content'].toString())
        .join('\n');
    expect(systemContext, contains('Current task progress:'));
    expect(systemContext, contains('- completed: Inspect the project'));
    expect(systemContext,
        contains('- in_progress: Implement the requested change'));
  });

  testWidgets('searches discovered models and sends the selected model id', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    late http.BaseRequest sentRequest;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        sentRequest = request;
        return _chatResponse(
            '${_sseChunk('Selected model reply')}data: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    expect(find.byKey(const Key('model.effort.selector')), findsNothing);
    await tester.tap(find.byKey(const Key('model.selector')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('model.picker.search')),
      'fast',
    );
    await tester.pumpAndSettle();

    expect(find.text('Fast model'), findsOneWidget);
    expect(find.text('32.8k context'), findsOneWidget);
    expect(find.text('Test provider'), findsOneWidget);
    expect(find.text('test-model'), findsNothing);
    await tester.tap(
      find.byKey(
        const Key(
          'model.option.Test provider:https://provider.example.test/v1.fast-model',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test provider · Fast model'), findsOneWidget);
    expect(find.byKey(const Key('model.effort.selector')), findsOneWidget);
    await tester.tap(find.byKey(const Key('model.effort.selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model.effort.option.max')));
    await tester.pumpAndSettle();
    expect(find.text('Max'), findsOneWidget);

    await _selectDiscoveredModel(tester, 'test-model');
    expect(find.byKey(const Key('model.effort.selector')), findsNothing);
    await _selectDiscoveredModel(tester, 'fast-model');
    expect(find.text('Max'), findsOneWidget);

    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Use the selected model',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(tester, find.text('Selected model reply'));

    final body =
        jsonDecode((sentRequest as http.Request).body) as Map<String, dynamic>;
    expect(body['model'], 'fast-model');
    expect(body['reasoning_effort'], 'xhigh');
    expect(body.containsKey('tools'), isFalse);
    expect(find.text('Selected model reply'), findsOneWidget);
  });

  testWidgets('does not run an unexpected tool from a model without tools', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    var requestCount = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requestCount++;
        return _chatResponse(
          '${_sseToolCall()}data: [DONE]\n\n',
        );
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await _selectDiscoveredModel(tester, 'fast-model');
    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Read a file',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text(
        'The selected model or permission mode does not allow project tools.',
      ),
    );

    expect(requestCount, 1);
    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText())
        .toList();
    expect(
      find.text(
          'The selected model or permission mode does not allow project tools.'),
      findsOneWidget,
      reason: renderedText.join('\n'),
    );
    expect(find.text('Checking files.'), findsNothing);
  });

  testWidgets('shows approved edit diffs and lists only applied changes', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-edit-ui-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    final source = File(
      '${projectDirectory.path}${Platform.pathSeparator}main.dart',
    );
    await tester.runAsync(
      () => source.writeAsString('const greeting = "Hello";\n'),
    );
    final project = Project(
      id: 'editable-project',
      name: 'Editable project',
      path: projectDirectory.path,
    );

    var responseIndex = 0;
    final editArguments = jsonEncode({
      'file_path': 'main.dart',
      'old_string': 'Hello',
      'new_string': 'Penguin',
    });
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        final body = switch (responseIndex++) {
          0 || 3 => _sseToolCall(
              name: 'read_project_file',
              arguments: '{"path":"main.dart"}',
              id: 'read-$responseIndex',
            ),
          1 => _sseToolCall(
              name: 'edit_project_file',
              arguments: editArguments,
              id: 'edit-denied',
            ),
          2 => _sseChunk('The denied edit was not applied.'),
          4 => _sseToolCall(
              name: 'edit_project_file',
              arguments: editArguments,
              id: 'edit-approved',
            ),
          _ => _sseChunk('The approved edit was applied.'),
        };
        return _chatResponse('$body\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: [project],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);
    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('project.access.option.approveForMe'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Replace the greeting',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat.tool.deny.edit-denied')),
    );

    expect(find.text('Edit a file'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );
    final denyEditButton = find.byKey(const Key('chat.tool.deny.edit-denied'));
    await tester.ensureVisible(denyEditButton);
    await tester.pump();
    await tester.tap(denyEditButton);
    await _pumpUntilVisible(
        tester, find.text('The denied edit was not applied.'));
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );
    expect(find.text('The denied edit was not applied.'), findsOneWidget);

    await _startProjectChatFor(tester, project.id);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Replace the greeting safely',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat.tool.approve.edit-approved')),
    );
    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Hello";\n',
    );
    final approveEditButton =
        find.byKey(const Key('chat.tool.approve.edit-approved'));
    await tester.ensureVisible(approveEditButton);
    await tester.pump();
    await tester.tap(approveEditButton);
    await _pumpUntilVisible(
      tester,
      find.text('The approved edit was applied.'),
    );

    expect(
      await tester.runAsync(source.readAsString),
      'const greeting = "Penguin";\n',
    );
    expect(find.text('The approved edit was applied.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('topbar.changes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('changes.list')), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('Editable project · Replace the greeting safely'),
        findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Penguin'), findsOneWidget);
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
      _testApp(
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
    await _pumpUntilVisible(tester, find.text('Hello from the model.'));

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
    expect(
      (body['tools'] as List<dynamic>).where((tool) =>
          ((tool as Map<String, dynamic>)['function']
              as Map<String, dynamic>)['name'] ==
          'delegate_task'),
      isEmpty,
    );
    final messages = body['messages'] as List<dynamic>;
    expect(messages.last, {'role': 'user', 'content': 'Explain this value'});
    expect(messages.first['role'], 'system');
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
      _testApp(
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
    await _pumpUntilVisible(tester, find.text('I see the selected file.'));

    final body =
        jsonDecode((sentRequest as http.Request).body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>;
    expect(messages, hasLength(2));
    expect(messages.last['role'], 'user');
    expect(messages.last['content'], contains('lib/example.dart'));
    expect(messages.last['content'], contains('const answer = 42;'));
    expect(messages.last['content'], contains('Explain this code'));
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
      _testApp(
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
    await _pumpUntilVisible(tester, find.byKey(const Key('composer.stop')));
    stream.add(utf8.encode(_sseChunk('Partial answer')));
    await _pumpUntilVisible(tester, find.text('Partial answer'));

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
      _testApp(
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
    await _pumpUntilVisible(tester, find.textContaining('HTTP 401'));
    expect(find.textContaining('HTTP 401'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('chat.messages')),
        matching: find.text('Try this request again'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await _pumpUntilVisible(tester, find.text('Recovered'));
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

  testWidgets('keeps subagents off until enabled in Settings', (tester) async {
    await _setDesktopSize(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    expect(find.text('Subagents are off'), findsOneWidget);
    expect(find.byKey(const Key('agents.create')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('agents.create')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings.subagents')), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byKey(const Key('settings.subagents'))).value,
      isFalse,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<ResponseDetail>>(
            find.byKey(const Key('settings.responseDetail')),
          )
          .initialValue,
      ResponseDetail.modelDefault,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<ReasoningSummary>>(
            find.byKey(const Key('settings.reasoningSummary')),
          )
          .initialValue,
      ReasoningSummary.automatic,
    );
    await tester
        .ensureVisible(find.byKey(const Key('settings.responseDetail')));
    await tester.tap(find.byKey(const Key('settings.responseDetail')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings.reasoningSummary')),
    );
    await tester.tap(find.byKey(const Key('settings.reasoningSummary')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detailed').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('settings.subagents')));
    await tester.tap(find.byKey(const Key('settings.subagents')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(find.byKey(const Key('settings.subagents'))).value,
      isTrue,
    );
    expect(
      await tester.runAsync(
        () =>
            SharedPreferencesAsync().getBool('penguin_code.subagents_enabled'),
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const Key('sidebar.new-chat')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(find.byKey(const Key('settings.subagents'))).value,
      isTrue,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<ResponseDetail>>(
            find.byKey(const Key('settings.responseDetail')),
          )
          .initialValue,
      ResponseDetail.high,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<ReasoningSummary>>(
            find.byKey(const Key('settings.reasoningSummary')),
          )
          .initialValue,
      ReasoningSummary.detailed,
    );
    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    expect(find.text('Add a model provider'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topbar.changes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page.changes')), findsOneWidget);
    expect(
        find.text('Approved project edits will appear here.'), findsOneWidget);
  });

  testWidgets('delegates a focused task and returns its result to the parent', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    String? childTaskId;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final response = switch (responseIndex++) {
          0 => _sseToolCall(
              name: 'delegate_task',
              arguments: jsonEncode({
                'task': 'Inspect the authentication flow and summarize risks.',
              }),
              id: 'delegate-auth-review',
            ),
          1 => _sseChunk('The flow has one missing token expiry check.'),
          2 => _sseChunk('The review found one token expiry risk.'),
          3 =>
            _sseChunk('I verified the expiry check in the saved transcript.'),
          4 => _sseToolCall(
              name: 'list_subagent_tasks',
              arguments: '{}',
              id: 'list-auth-review',
            ),
          5 => () {
              final messages = requests.last['messages'] as List<dynamic>;
              final listing = messages
                  .whereType<Map<String, dynamic>>()
                  .lastWhere((message) => message['role'] == 'tool');
              childTaskId = RegExp(r'id: ([^\n]+)')
                  .firstMatch(listing['content'].toString())
                  ?.group(1);
              return _sseToolCall(
                name: 'continue_subagent_task',
                arguments: jsonEncode({
                  'task_id': childTaskId,
                  'message': 'Summarize the verified finding.',
                }),
                id: 'continue-auth-review',
              );
            }(),
          6 => _sseChunk('The finding is an expired token check.'),
          _ => _sseChunk('The continued review confirms the expiry finding.'),
        };
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('settings.subagents')));
    await tester.tap(find.byKey(const Key('settings.subagents')));
    await tester.pumpAndSettle();
    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Use a subagent to review authentication.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text('The review found one token expiry risk.'),
    );

    expect(requests, hasLength(3));
    final parentToolNames = (requests.first['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(parentToolNames, contains('delegate_task'));
    final childMessages = requests[1]['messages'] as List<dynamic>;
    expect(childMessages.last['role'], 'user');
    expect(
      childMessages.last['content'],
      'Inspect the authentication flow and summarize risks.',
    );
    expect(
      childMessages.any((message) =>
          (message as Map<String, dynamic>)['content'] ==
          'Use a subagent to review authentication.'),
      isFalse,
    );
    final parentToolResult = (requests[2]['messages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .lastWhere((message) => message['role'] == 'tool');
    expect(
      parentToolResult['content'],
      contains('The flow has one missing token expiry check.'),
    );

    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    expect(find.text('Inspect the authentication flow and summarize risks.'),
        findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(
      find.textContaining('The flow has one missing token expiry check.'),
      findsOneWidget,
    );

    final savedTasks = await tester.runAsync(_testDataStore.loadConversations);
    expect(savedTasks, isNotNull);
    expect(
      savedTasks!.where((saved) => saved.agentTask != null),
      hasLength(1),
    );
    final task = savedTasks.singleWhere((saved) => saved.agentTask != null);
    expect(task.agentTask?.status, AgentTaskStatus.completed);
    expect(task.agentTask?.parentChatId, isNotNull);
    expect(task.messages, hasLength(2));

    await tester.tap(find.byKey(Key('agents.continue.${task.agentTask!.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agents.task.followup.input')),
      'Verify the finding and update the summary.',
    );
    await tester.tap(find.byKey(const Key('agents.task.followup.send')));
    await _pumpUntilVisible(
      tester,
      find.text('I verified the expiry check in the saved transcript.'),
    );

    expect(requests, hasLength(4));
    final continuedMessages = requests.last['messages'] as List<dynamic>;
    expect(
      continuedMessages.whereType<Map<String, dynamic>>().map(
            (message) => message['content'],
          ),
      containsAll([
        'Inspect the authentication flow and summarize risks.',
        'The flow has one missing token expiry check.',
        'Verify the finding and update the summary.',
      ]),
    );

    await tester.tap(find.text('Chat').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'List my subagent tasks and summarize the review.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text('The continued review confirms the expiry finding.'),
    );
    expect(childTaskId, task.agentTask!.id);
    expect(requests, hasLength(8));
    final managementTools = (requests[4]['tools'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();
    expect(
        managementTools,
        containsAll([
          'list_subagent_tasks',
          'continue_subagent_task',
          'stop_subagent_task',
        ]));
    final childContinuationRequest = requests[6]['messages'] as List<dynamic>;
    expect(
      childContinuationRequest.whereType<Map<String, dynamic>>().any(
          (message) =>
              message['role'] == 'user' &&
              message['content'] == 'Summarize the verified finding.'),
      isTrue,
    );
    final continuationResult = (requests[7]['messages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .lastWhere((message) => message['role'] == 'tool');
    expect(
      continuationResult['content'].toString(),
      contains('The finding is an expired token check.'),
    );

    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('settings.subagents')));
    await tester.tap(find.byKey(const Key('settings.subagents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    await _pumpUntilVisible(
      tester,
      find.text('Inspect the authentication flow and summarize risks.'),
    );
    expect(
      find.text('Inspect the authentication flow and summarize risks.'),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(Key('agents.continue.${task.agentTask!.id}')),
          )
          .onPressed,
      isNull,
    );
    final finalSavedTasks =
        await tester.runAsync(_testDataStore.loadConversations);
    expect(
      finalSavedTasks!
          .singleWhere((saved) => saved.agentTask != null)
          .agentTask
          ?.result,
      'The finding is an expired token check.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_testApp(initialProjects: const [_testProject]));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    await _pumpUntilVisible(
      tester,
      find.text('Inspect the authentication flow and summarize risks.'),
    );
    expect(
      find.text('Inspect the authentication flow and summarize risks.'),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsOneWidget);
    expect(find.textContaining('The finding is an expired token check.'),
        findsOneWidget);
  });

  testWidgets('loads nested AGENTS.md before accessing that project folder', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-agents-context-'),
    ))!;
    final nestedDirectory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}packages',
    )..createSync();
    await tester.runAsync(() async {
      await File('${projectDirectory.path}${Platform.pathSeparator}AGENTS.md')
          .writeAsString('Root instruction: use the project format.');
      await File('${nestedDirectory.path}${Platform.pathSeparator}AGENTS.md')
          .writeAsString('Nested instruction: inspect package rules first.');
      await File('${nestedDirectory.path}${Platform.pathSeparator}README.md')
          .writeAsString('Package contents.');
    });
    addTearDown(() => tester.runAsync(
          () => projectDirectory.delete(recursive: true),
        ));
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final response = responseIndex++ == 0
            ? _sseToolCall(
                name: 'read_project_file',
                arguments: '{"path":"packages/README.md"}',
                id: 'read-package-readme',
              )
            : _sseChunk('I reviewed the package instructions first.');
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    final project = Project(
      id: 'agents-project',
      name: 'Instruction project',
      path: projectDirectory.path,
    );
    await tester.pumpWidget(
      _testApp(initialProjects: [project], chatClient: client),
    );
    await tester.pumpAndSettle();
    await _configureProvider(tester);
    await _startProjectChatFor(tester, project.id);
    await tester.tap(find.byKey(const Key('project.access.menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project.access.option.approveForMe')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Read the package README and summarize it.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(
      tester,
      find.text('I reviewed the package instructions first.'),
    );

    expect(requests, hasLength(2));
    String systemContext(Map<String, dynamic> request) =>
        (request['messages'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .where((message) => message['role'] == 'system')
            .map((message) => message['content'].toString())
            .join('\n');
    expect(
      systemContext(requests.first),
      contains('Root instruction: use the project format.'),
    );
    expect(
      systemContext(requests.first),
      isNot(contains('Nested instruction: inspect package rules first.')),
    );
    expect(
      systemContext(requests.last),
      contains('Nested instruction: inspect package rules first.'),
    );
    final pausedToolResult = (requests.last['messages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .lastWhere((message) => message['role'] == 'tool');
    expect(pausedToolResult['content'], contains('action was paused'));
    expect(pausedToolResult['content'], isNot(contains('Package contents.')));
  });

  testWidgets('subagent file actions use the selected approval mode', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final projectDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('penguin-subagent-approval-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() => projectDirectory.delete(recursive: true)),
    );
    await tester.runAsync(
      () => File('${projectDirectory.path}${Platform.pathSeparator}README.md')
          .writeAsString('# Test project\n'),
    );
    final project = Project(
      id: 'subagent-project',
      name: 'Subagent project',
      path: projectDirectory.path,
    );
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        final response = switch (responseIndex++) {
          0 => _sseToolCall(
              name: 'delegate_task',
              arguments:
                  jsonEncode({'task': 'Read README.md and summarize it.'}),
              id: 'delegate-readme',
            ),
          1 => _sseToolCall(
              name: 'read_project_file',
              arguments: '{"path":"README.md"}',
              id: 'child-readme-read',
            ),
          2 => _sseChunk('The README identifies this as a test project.'),
          _ => _sseChunk('The README review is complete.'),
        };
        return _chatResponse('$response\ndata: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: [project],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('settings.subagents')));
    await tester.tap(find.byKey(const Key('settings.subagents')));
    await tester.pumpAndSettle();
    await _startProjectChatFor(tester, project.id);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Delegate a read-only review of the project README.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('topbar.agents')));
    await tester.pumpAndSettle();
    await _pumpUntilVisible(
        tester, find.text('Read README.md and summarize it.'));
    final approvalButton = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('chat.tool.approve.');
    });
    await _pumpUntilVisible(tester, approvalButton);
    expect(find.text('Approval needed'), findsOneWidget);
    await tester.ensureVisible(approvalButton);
    await tester.tap(approvalButton);
    await tester.tap(find.text('Chat').first);
    await _pumpUntilVisible(
        tester, find.text('The README review is complete.'));

    expect(requests, hasLength(4));
    final childReadResult = requests[2]['messages'] as List<dynamic>;
    expect(childReadResult.last['role'], 'tool');
    expect(childReadResult.last['content'], contains('# Test project'));
    final parentToolResult = (requests[3]['messages'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .lastWhere((message) => message['role'] == 'tool');
    expect(
      parentToolResult['content'],
      contains('The README identifies this as a test project.'),
    );
  });

  testWidgets('adds output and reasoning preferences as provider guidance', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    late Map<String, dynamic> requestBody;
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requestBody =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        return _chatResponse(
            '${_sseChunk('Preference check complete.')}data: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(
      _testApp(
        initialProjects: const [_testProject],
        chatClient: client,
      ),
    );
    await tester.pumpAndSettle();

    await _configureProvider(tester);
    await tester.tap(find.byKey(const Key('sidebar.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('settings.responseDetail')));
    await tester.tap(find.byKey(const Key('settings.responseDetail')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings.reasoningSummary')),
    );
    await tester.tap(find.byKey(const Key('settings.reasoningSummary')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detailed').last);
    await tester.pumpAndSettle();

    await _startProjectChat(tester);
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Explain how the settings apply.',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntilVisible(tester, find.text('Preference check complete.'));

    final messages = requestBody['messages'] as List<dynamic>;
    final systemMessage = messages.first as Map<String, dynamic>;
    final instructions = systemMessage['content'] as String;
    expect(instructions, contains('Give a thorough response'));
    expect(instructions, contains('detailed high-level summary'));
    expect(instructions, contains('Never reveal hidden chain-of-thought'));
    expect(requestBody.containsKey('verbosity'), isFalse);
    expect(requestBody.containsKey('reasoning'), isFalse);
  });

  testWidgets('runs a bounded goal through evaluation and continuation', (
    tester,
  ) async {
    await _setDesktopSize(tester);
    final requests = <Map<String, dynamic>>[];
    var responseIndex = 0;
    final responses = [
      _sseChunk('The first run found one test that still needs attention.'),
      _sseChunk(
        'VERDICT: not_yet_met\nREASON: One test still needs to be run.',
      ),
      _sseChunk('All widget tests passed with exit code 0.'),
      _sseChunk('VERDICT: met\nREASON: The test run returned exit code 0.'),
    ];
    final client = OpenAiCompatibleChatClient(
      client: _FakeChatClient((request) async {
        requests.add(
          jsonDecode((request as http.Request).body) as Map<String, dynamic>,
        );
        return _chatResponse('${responses[responseIndex++]}data: [DONE]\n\n');
      }),
    );
    await tester.pumpWidget(_testApp(chatClient: client));
    await tester.pumpAndSettle();
    await _configureProvider(tester);

    await tester.enterText(
      find.byKey(const Key('composer.input')),
      '/goal all widget tests pass',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    for (var attempt = 0; attempt < 160 && requests.length < 4; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();

    expect(requests, hasLength(4));
    final initialMessages = requests.first['messages'] as List<dynamic>;
    expect(initialMessages.last['content'], 'all widget tests pass');
    expect(initialMessages.first['content'],
        contains('Active goal for this chat'));
    expect(requests[1].containsKey('tools'), isFalse);
    final continuationMessages = requests[2]['messages'] as List<dynamic>;
    expect(continuationMessages.last['content'],
        contains('Continue working toward the active goal'));
    final goalCheckMessages = requests[3]['messages'] as List<dynamic>;
    expect(
        goalCheckMessages.first['content'], contains('completion evaluator'));
    expect(find.byKey(const Key('chat.goal-card')), findsOneWidget);
    expect(find.text('Achieved · 2/6 checks'), findsOneWidget);
    expect(find.textContaining('Goal achieved:'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('composer.input')), '/goal');
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Goal achieved (2/6 checks)'), findsOneWidget);
    expect(requests, hasLength(4));

    await tester.enterText(
      find.byKey(const Key('composer.input')),
      '/goal clear',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.goal-card')), findsNothing);
    expect(find.textContaining('Goal cleared:'), findsOneWidget);
    expect(requests, hasLength(4));
    expect(tester.takeException(), isNull);
  });
}

PenguinCodeApp _testApp({
  List<Project> initialProjects = const [],
  OpenAiCompatibleChatClient? chatClient,
  Future<List<ChatAttachment>> Function(
    Project project,
    List<ChatAttachment> alreadyAttached,
  )? attachmentPicker,
  McpTransportFactory? mcpTransportFactory,
  McpCredentialStore? mcpCredentialStore,
}) =>
    PenguinCodeApp(
      initialProjects: initialProjects,
      chatClient: chatClient,
      attachmentPicker: attachmentPicker,
      mcpTransportFactory: mcpTransportFactory,
      mcpCredentialStore: mcpCredentialStore,
      dataStore: _testDataStore,
    );

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
  await _createNewChat(tester);
  if (find.byKey(const Key('composer.project.select')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('composer.project.select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project.select.test-project')));
    await tester.pumpAndSettle();
    await _createNewChat(tester);
  }
  await _pumpUntilVisible(
    tester,
    find.byKey(const Key('project.access.menu')),
  );
}

Future<void> _startProjectChatFor(
  WidgetTester tester,
  String projectId,
) async {
  await _createNewChat(tester);
  if (find.byKey(const Key('composer.project.select')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('composer.project.select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('project.select.$projectId')));
    await tester.pumpAndSettle();
    await _createNewChat(tester);
  }
  await _pumpUntilVisible(
    tester,
    find.byKey(const Key('project.access.menu')),
  );
}

Future<void> _createNewChat(WidgetTester tester) async {
  if (find.byKey(const Key('sidebar.new-chat')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('sidebar.toggle')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('sidebar.new-chat')));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(finder, findsOneWidget);
}

Future<void> _selectDiscoveredModel(
  WidgetTester tester,
  String modelId,
) async {
  await tester.tap(find.byKey(const Key('model.selector')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      Key(
        'model.option.Test provider:https://provider.example.test/v1.$modelId',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _sseChunk(String content) => 'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': content}
            }
          ]
        })}\n\n';

String _sseToolCall({
  String name = 'read_project_file',
  String arguments = '{"path":"README.md"}',
  String id = 'call-1',
}) =>
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': id,
                    'function': {
                      'name': name,
                      'arguments': arguments,
                    },
                  },
                ],
              },
            },
          ],
        })}\n\n';

String _sseToolCalls(List<Map<String, String>> calls) => 'data: ${jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  for (var index = 0; index < calls.length; index++)
                    {
                      'index': index,
                      'id': calls[index]['id'],
                      'function': {
                        'name': calls[index]['name'],
                        'arguments': calls[index]['arguments'],
                      },
                    },
                ],
              },
            },
          ],
        })}\n\n';

http.StreamedResponse _modelsResponse() => http.StreamedResponse(
      Stream.value(
        utf8.encode(jsonEncode({
          'data': [
            {'id': 'test-model', 'supports_tools': true},
            {
              'id': 'fast-model',
              'display_name': 'Fast model',
              'context_length': 32768,
              'supports_tools': false,
              'reasoningEfforts': {
                'off': null,
                'low': 'low',
                'max': 'xhigh',
              },
            },
          ],
        })),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );

http.StreamedResponse _chatResponse(String body, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status);

class _FakeChatClient extends http.BaseClient {
  _FakeChatClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      request.method == 'GET'
          ? Future.value(_modelsResponse())
          : handler(request);
}

class _RecordingMcpCredentialStore implements McpCredentialStore {
  final savedHeaders = <String, Map<String, String>>{};

  @override
  Future<Map<String, String>> readHeaders(String serverId) async =>
      savedHeaders[serverId] ?? const {};

  @override
  Future<void> writeHeaders(
    String serverId,
    Map<String, String> headers,
  ) async {
    savedHeaders[serverId] = Map.unmodifiable(headers);
  }

  @override
  Future<void> deleteHeaders(String serverId) async {
    savedHeaders.remove(serverId);
  }
}

class _AppFakeMcpTransport implements McpStdioTransport {
  final _lines = StreamController<String>();
  final toolCalls = <Map<String, dynamic>>[];

  @override
  Stream<String> get lines => _lines.stream;

  @override
  void sendLine(String line) {
    final request = jsonDecode(line) as Map<String, dynamic>;
    final method = request['method'];
    if (method == 'notifications/initialized') return;
    final Map<String, dynamic> result;
    if (method == 'initialize') {
      result = {
        'protocolVersion': '2025-11-25',
        'serverInfo': {'name': 'Test MCP', 'version': '1'},
        'capabilities': {'tools': <String, dynamic>{}},
      };
    } else if (method == 'tools/list') {
      result = {
        'tools': [
          {
            'name': 'lookup',
            'description': 'Look up a test record.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'}
              },
              'required': ['query'],
            },
          },
        ],
      };
    } else if (method == 'tools/call') {
      toolCalls.add(Map<String, dynamic>.from(request['params'] as Map));
      result = {
        'content': [
          {'type': 'text', 'text': 'MCP executed only after approval.'},
        ],
        'isError': false,
      };
    } else {
      return;
    }
    _lines.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': request['id'],
      'result': result,
    }));
  }

  @override
  Future<void> close() => _lines.close();
}
