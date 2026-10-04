import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/penguin_code_app.dart';

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
    expect(find.text(r'C:\Projects\penguin-code'), findsOneWidget);
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

  testWidgets('adds a provider profile to the model selector preview', (
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
      'preview-only-secret',
    );
    await tester.tap(find.byKey(const Key('provider.save')));
    await tester.pumpAndSettle();

    expect(find.text('On-device model · qwen3:8b'), findsOneWidget);
    expect(
      find.text(
        'Preview profile saved for this session. No connection was made.',
      ),
      findsOneWidget,
    );
    expect(find.text('preview-only-secret'), findsNothing);
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
