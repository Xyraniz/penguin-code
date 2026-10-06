import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class SkillsHubEntry {
  const SkillsHubEntry({
    required this.id,
    required this.name,
    required this.source,
    required this.installCount,
  });

  final String id;
  final String name;
  final String source;
  final int installCount;

  List<String> get pathParts => id.split('/').skip(2).toList(growable: false);
  String get owner => source.split('/').first;
  String get repository => source.split('/').last;
  String get pageUrl => 'https://skills.sh/$id';
}

class SkillsHubPreview {
  const SkillsHubPreview({
    required this.entry,
    required this.content,
    required this.description,
    required this.license,
    required this.revision,
  });

  final SkillsHubEntry entry;
  final String content;
  final String description;
  final String? license;
  final String revision;
}

class SkillsHubException implements Exception {
  const SkillsHubException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SkillsHubService {
  SkillsHubService({
    http.Client? client,
    this.skillsHubHost = 'skills.sh',
    this.githubApiHost = 'api.github.com',
  })  : _client = client,
        _ownsClient = client == null;

  static const maxSkillBytes = 32 * 1024;
  static const _maxResponseBytes = 3 * 1024 * 1024;
  static const _maxSearchResults = 20;
  static const _timeout = Duration(seconds: 15);
  static final _sourcePart = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');

  final String skillsHubHost;
  final String githubApiHost;
  http.Client? _client;
  final bool _ownsClient;

  Future<List<SkillsHubEntry>> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2 || normalizedQuery.length > 100) {
      throw const SkillsHubException('Search with 2 to 100 characters.');
    }
    final uri = Uri.https(skillsHubHost, 'api/search', {
      'q': normalizedQuery,
      'limit': '20',
    });
    final response = await _get(uri, headers: const {
      'Accept': 'application/json',
    });
    if (response.statusCode != HttpStatus.ok) {
      throw const SkillsHubException('The skills catalog is unavailable.');
    }
    final decoded = _decodeJson(response.bodyBytes);
    final rawSkills = decoded is Map ? decoded['skills'] : null;
    if (rawSkills is! List) {
      throw const SkillsHubException(
          'The skills catalog returned invalid data.');
    }
    final results = <SkillsHubEntry>[];
    final seen = <String>{};
    for (final rawSkill in rawSkills) {
      if (rawSkill is! Map) continue;
      final id = rawSkill['id'] is String
          ? (rawSkill['id'] as String).trim()
          : rawSkill['slug'] is String
              ? (rawSkill['slug'] as String).trim()
              : '';
      final source = rawSkill['source'] is String
          ? (rawSkill['source'] as String).trim()
          : '';
      final name =
          rawSkill['name'] is String ? (rawSkill['name'] as String).trim() : '';
      final pathParts = id.split('/');
      final sourceParts = source.split('/');
      if (pathParts.length < 3 ||
          sourceParts.length != 2 ||
          pathParts[0] != sourceParts[0] ||
          pathParts[1] != sourceParts[1] ||
          pathParts.any((part) => !_sourcePart.hasMatch(part)) ||
          sourceParts.any((part) => !_sourcePart.hasMatch(part)) ||
          name.isEmpty ||
          name.length > 100 ||
          !seen.add(id)) {
        continue;
      }
      final installs = rawSkill['installs'];
      results.add(SkillsHubEntry(
        id: id,
        name: name,
        source: source,
        installCount: installs is int && installs > 0 ? installs : 0,
      ));
      if (results.length >= _maxSearchResults) break;
    }
    return List.unmodifiable(results);
  }

  Future<SkillsHubPreview> inspect(SkillsHubEntry entry) async {
    _validateEntry(entry);
    final repositoryResponse = await _get(
      Uri.https(githubApiHost, 'repos/${entry.owner}/${entry.repository}'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (repositoryResponse.statusCode != HttpStatus.ok) {
      throw const SkillsHubException('Could not open this skill source.');
    }
    final repository = _decodeJson(repositoryResponse.bodyBytes);
    if (repository is! Map || repository['default_branch'] is! String) {
      throw const SkillsHubException('The skill source has no default branch.');
    }
    final branch = repository['default_branch'] as String;
    if (branch.isEmpty || branch.length > 200 || branch.contains('..')) {
      throw const SkillsHubException('The skill source has an invalid branch.');
    }
    final treeUri = Uri.https(
      githubApiHost,
      'repos/${entry.owner}/${entry.repository}/git/trees/$branch',
      {'recursive': '1'},
    );
    final treeResponse = await _get(treeUri, headers: const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    });
    if (treeResponse.statusCode != HttpStatus.ok) {
      throw const SkillsHubException('Could not read the skill repository.');
    }
    final tree = _decodeJson(treeResponse.bodyBytes);
    final nodes = tree is Map ? tree['tree'] : null;
    if (nodes is! List) {
      throw const SkillsHubException('The skill repository tree is invalid.');
    }
    final suffix = '${entry.pathParts.join('/')}/SKILL.md';
    final candidates = nodes.whereType<Map<dynamic, dynamic>>().where((node) {
      final path = node['path'];
      return node['type'] == 'blob' &&
          path is String &&
          !path.split('/').any((part) => part == '.' || part == '..') &&
          (path == suffix || path.endsWith('/$suffix')) &&
          node['sha'] is String &&
          node['size'] is int &&
          (node['size'] as int) > 0 &&
          (node['size'] as int) <= maxSkillBytes;
    }).toList(growable: false);
    if (candidates.length != 1) {
      throw const SkillsHubException(
        'Could not find one safe SKILL.md file for this catalog entry.',
      );
    }
    final blobSha = candidates.single['sha'] as String;
    if (!RegExp(r'^[a-fA-F0-9]{40,64}$').hasMatch(blobSha)) {
      throw const SkillsHubException('The skill source revision is invalid.');
    }
    final blobResponse = await _get(
      Uri.https(
        githubApiHost,
        'repos/${entry.owner}/${entry.repository}/git/blobs/$blobSha',
      ),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (blobResponse.statusCode != HttpStatus.ok) {
      throw const SkillsHubException('Could not download this skill preview.');
    }
    final blob = _decodeJson(blobResponse.bodyBytes);
    if (blob is! Map ||
        blob['encoding'] != 'base64' ||
        blob['content'] is! String) {
      throw const SkillsHubException('The skill preview is invalid.');
    }
    late final String content;
    try {
      final bytes = base64
          .decode((blob['content'] as String).replaceAll(RegExp(r'\s+'), ''));
      if (bytes.isEmpty || bytes.length > maxSkillBytes) {
        throw const SkillsHubException(
            'This SKILL.md exceeds the 32 KiB limit.');
      }
      content = utf8.decode(bytes);
    } on FormatException {
      throw const SkillsHubException('This SKILL.md is not valid UTF-8.');
    }
    if (content.trim().isEmpty || content.contains('\u0000')) {
      throw const SkillsHubException('This SKILL.md is empty or invalid.');
    }
    final license = repository['license'] is Map
        ? (repository['license'] as Map)['spdx_id']
        : null;
    return SkillsHubPreview(
      entry: entry,
      content: content,
      description: _frontMatterValue(content, 'description'),
      license: license is String && license != 'NOASSERTION' ? license : null,
      revision: blobSha,
    );
  }

  Future<Directory> install(
    SkillsHubPreview preview, {
    required Directory skillsDirectory,
  }) async {
    _validateEntry(preview.entry);
    if (!RegExp(r'^[a-fA-F0-9]{40,64}$').hasMatch(preview.revision) ||
        preview.content.isEmpty ||
        utf8.encode(preview.content).length > maxSkillBytes ||
        preview.content.contains('\u0000')) {
      throw const SkillsHubException('This skill cannot be installed.');
    }
    await skillsDirectory.create(recursive: true);
    final segments = [
      'community',
      ...preview.entry.source.split('/'),
      ...preview.entry.pathParts,
    ];
    final folderPrefix = segments
        .join('-')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    final folderName =
        '${folderPrefix.substring(0, folderPrefix.length.clamp(0, 160).toInt())}-${preview.revision.substring(0, 8)}';
    final destination = Directory(
      '${skillsDirectory.path}${Platform.pathSeparator}$folderName',
    );
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const SkillsHubException('This skill is already installed.');
    }
    final temporary = Directory(
      '${skillsDirectory.path}${Platform.pathSeparator}.install-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.create();
      await File(
        '${temporary.path}${Platform.pathSeparator}SKILL.md',
      ).writeAsString(preview.content, flush: true);
      await File(
        '${temporary.path}${Platform.pathSeparator}.penguin-skill.json',
      ).writeAsString(
          jsonEncode({
            'source': preview.entry.pageUrl,
            'repository': 'https://github.com/${preview.entry.source}',
            'revision': preview.revision,
            'license': preview.license,
            'installedAt': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true);
      await temporary.rename(destination.path);
      return destination;
    } on FileSystemException {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      rethrow;
    }
  }

  void _validateEntry(SkillsHubEntry entry) {
    final parts = entry.id.split('/');
    final source = entry.source.split('/');
    if (parts.length < 3 ||
        source.length != 2 ||
        parts[0] != source[0] ||
        parts[1] != source[1] ||
        parts.any((part) =>
            !_sourcePart.hasMatch(part) || part == '.' || part == '..') ||
        source.any((part) =>
            !_sourcePart.hasMatch(part) || part == '.' || part == '..') ||
        entry.pathParts.isEmpty) {
      throw const SkillsHubException('This skill source is invalid.');
    }
  }

  Future<http.Response> _get(Uri uri,
      {required Map<String, String> headers}) async {
    try {
      final response = await (_client ??= http.Client())
          .get(uri, headers: headers)
          .timeout(_timeout);
      if (response.bodyBytes.length > _maxResponseBytes) {
        throw const SkillsHubException(
            'The skill source response is too large.');
      }
      return response;
    } on SkillsHubException {
      rethrow;
    } on Object {
      throw const SkillsHubException(
        'Could not connect to the skills catalog. Check your connection and try again.',
      );
    }
  }

  Object? _decodeJson(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const SkillsHubException('The skill source returned invalid data.');
    }
  }

  String _frontMatterValue(String content, String key) {
    if (!content.startsWith('---')) return '';
    final end = content.indexOf('\n---', 3);
    if (end < 0) return '';
    for (final line in content.substring(3, end).split('\n')) {
      final separator = line.indexOf(':');
      if (separator < 0 || line.substring(0, separator).trim() != key) continue;
      final value = line
          .substring(separator + 1)
          .trim()
          .replaceAll(RegExp(r'''^["']|["']$'''), '');
      return value.substring(0, value.length.clamp(0, 500).toInt());
    }
    return '';
  }

  void close() {
    if (_ownsClient) _client?.close();
  }
}
