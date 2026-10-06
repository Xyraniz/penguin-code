import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/screens/skills_screen.dart';
import 'package:penguin_code/services/skills_hub.dart';

void main() {
  testWidgets('searches, previews, and installs only after explicit review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const skill = SkillsHubEntry(
      id: 'example/skills/accessibility-review',
      name: 'Accessibility review',
      source: 'example/skills',
      installCount: 42,
    );
    const preview = SkillsHubPreview(
      entry: skill,
      content: '# Accessibility review\n\nReview keyboard navigation.',
      description: 'Check practical accessibility requirements.',
      license: 'MIT',
      revision: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    var searchedQuery = '';
    SkillsHubPreview? installedPreview;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SkillsScreen(
          isMaterial3Installed: false,
          isMaterial3Active: false,
          isLibraryReady: true,
          isUpdatingLibrary: false,
          onAddMaterial3: () async => true,
          onRemoveMaterial3: () async => true,
          onUseMaterial3: () {},
          pendingProposals: const [],
          onReviewProposal: (_, {required approve}) async => true,
          localSkills: const [],
          activeSkillIds: const {},
          skillsDirectoryPath: r'C:\Users\Test\Documents\Penguin-code\Skills',
          onSkillActiveChanged: (_, __) {},
          onRefreshLocalSkills: () async {},
          onSearchSkills: (query) async {
            searchedQuery = query;
            return const [skill];
          },
          onInspectSkill: (_) async => preview,
          onInstallSkill: (value) async {
            installedPreview = value;
            return true;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('skills.marketplace.query')),
      'accessibility',
    );
    await tester.tap(find.byKey(const Key('skills.marketplace.search')));
    await tester.pumpAndSettle();

    expect(searchedQuery, 'accessibility');
    final inspectButton = find.byKey(
      const Key(
          'skills.marketplace.inspect.example/skills/accessibility-review'),
    );
    await tester.ensureVisible(inspectButton);
    await tester.tap(inspectButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Review keyboard navigation'), findsOneWidget);
    expect(installedPreview, isNull);

    await tester.tap(find.byKey(const Key('skills.marketplace.add')));
    await tester.pumpAndSettle();
    expect(installedPreview?.entry.id, skill.id);
    expect(find.byKey(const Key('skills.marketplace.preview')), findsNothing);
  });
}
