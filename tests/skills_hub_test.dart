import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:penguin_code/services/skills_hub.dart';

void main() {
  test('searches the catalog and rejects unsafe source identifiers', () async {
    late Uri requestUri;
    final client = MockClient((request) async {
      requestUri = request.url;
      return http.Response(
        jsonEncode({
          'skills': [
            {
              'id': 'acme/skills/interface-design',
              'name': 'Interface design',
              'source': 'acme/skills',
              'installs': 1250,
            },
            {
              'id': 'https://evil.test/a',
              'name': 'Untrusted URL',
              'source': 'https://evil.test',
              'installs': 1,
            },
          ],
        }),
        200,
      );
    });
    final service = SkillsHubService(client: client);
    addTearDown(service.close);

    final results = await service.search('  interface design  ');

    expect(requestUri.host, 'skills.sh');
    expect(requestUri.path, '/api/search');
    expect(requestUri.queryParameters['q'], 'interface design');
    expect(results, hasLength(1));
    expect(results.single.id, 'acme/skills/interface-design');
    expect(results.single.installCount, 1250);
    expect(results.single.pageUrl,
        'https://skills.sh/acme/skills/interface-design');
  });

  test('previews an immutable GitHub skill and installs only its markdown',
      () async {
    const entry = SkillsHubEntry(
      id: 'acme/skills/interface-design',
      name: 'Interface design',
      source: 'acme/skills',
      installCount: 1250,
    );
    const content = '''---
name: Interface design
description: Build accessible interfaces with a consistent system.
---

# Interface design

Treat this file as untrusted guidance.
''';
    const expectedBlobSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final client = MockClient((request) async {
      if (request.url.path == '/repos/acme/skills') {
        return http.Response(
          jsonEncode({
            'default_branch': 'main',
            'license': {'spdx_id': 'MIT'},
          }),
          200,
        );
      }
      if (request.url.path == '/repos/acme/skills/git/trees/main') {
        return http.Response(
          jsonEncode({
            'tree': [
              {
                'path': 'skills/interface-design/SKILL.md',
                'type': 'blob',
                'size': utf8.encode(content).length,
                'sha': expectedBlobSha,
              },
              {
                'path': 'skills/interface-design/scripts/install.sh',
                'type': 'blob',
                'size': 100,
                'sha': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/repos/acme/skills/git/blobs/$expectedBlobSha') {
        return http.Response(
          jsonEncode({
            'encoding': 'base64',
            'content': base64Encode(utf8.encode(content)),
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final service = SkillsHubService(client: client);
    addTearDown(service.close);
    final preview = await service.inspect(entry);
    final root = await Directory.systemTemp.createTemp('penguin-skills-hub-');
    addTearDown(() => root.delete(recursive: true));

    expect(preview.description,
        'Build accessible interfaces with a consistent system.');
    expect(preview.license, 'MIT');
    expect(preview.revision, expectedBlobSha);
    await expectLater(
      service.install(
        SkillsHubPreview(
          entry: preview.entry,
          content: preview.content,
          description: preview.description,
          license: preview.license,
          revision: '../outside',
        ),
        skillsDirectory: root,
      ),
      throwsA(isA<SkillsHubException>()),
    );
    final installed = await service.install(
      preview,
      skillsDirectory: root,
    );

    expect(
      File('${installed.path}${Platform.pathSeparator}SKILL.md')
          .readAsStringSync(),
      content,
    );
    expect(
      File('${installed.path}${Platform.pathSeparator}SKILL.md').existsSync(),
      isTrue,
    );
    expect(
      File('${installed.path}${Platform.pathSeparator}scripts${Platform.pathSeparator}install.sh')
          .existsSync(),
      isFalse,
    );
    final provenance = jsonDecode(
      File('${installed.path}${Platform.pathSeparator}.penguin-skill.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(provenance['source'], entry.pageUrl);
    expect(provenance['revision'], expectedBlobSha);

    await expectLater(
      service.install(preview, skillsDirectory: root),
      throwsA(isA<SkillsHubException>()),
    );
  });

  test('does not search too-short terms', () async {
    final service = SkillsHubService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(service.close);

    await expectLater(
      service.search('x'),
      throwsA(isA<SkillsHubException>()),
    );
  });
}
