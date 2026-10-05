import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/mcp_remote_transport.dart';
import 'package:penguin_code/services/mcp_stdio_client.dart';

void main() {
  test('uses Streamable HTTP sessions, auth headers, and JSON responses',
      () async {
    final requests = <http.Request>[];
    final transport = _FakeHttpClient((request) async {
      final captured = request as http.Request;
      requests.add(captured);
      expect(captured.headers['Authorization'], 'Bearer test-secret');
      if (captured.method == 'DELETE') {
        return http.StreamedResponse(const Stream.empty(), 405);
      }
      expect(captured.headers['Accept'], contains('application/json'));
      final message = jsonDecode(captured.body) as Map<String, dynamic>;
      switch (message['method']) {
        case 'initialize':
          return _jsonResponse(captured, {
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': _initializeResult(),
          }, headers: {
            'mcp-session-id': 'session-42'
          });
        case 'notifications/initialized':
          return http.StreamedResponse(const Stream.empty(), 202);
        case 'tools/list':
          expect(captured.headers['Mcp-Session-Id'], 'session-42');
          expect(captured.headers['MCP-Protocol-Version'], '2025-11-25');
          return _jsonResponse(captured, {
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': _toolList(),
          });
        case 'tools/call':
          return _jsonResponse(captured, {
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': {
              'content': [
                {'type': 'text', 'text': 'Remote result'},
              ],
            },
          });
        default:
          return http.StreamedResponse(const Stream.empty(), 405);
      }
    });
    final profile = _remoteServer(McpTransportType.http);
    final client = await _connect(profile, transport);

    expect(client.tools.map((tool) => tool.name), ['lookup']);
    expect(
      await client.callTool('lookup', {'query': 'penguin'}),
      'Remote result',
    );
    final methods = requests
        .where((request) => request.method == 'POST')
        .map((request) => (jsonDecode(request.body) as Map)['method'])
        .toList();
    expect(methods, [
      'initialize',
      'notifications/initialized',
      'tools/list',
      'tools/call',
    ]);
    await client.close();
  });

  for (final type in [McpTransportType.sse, McpTransportType.http]) {
    test('${type.name} connects to a legacy HTTP+SSE server', () async {
      final endpoint = Uri.parse('https://mcp.example.test/messages?session=7');
      final events = StreamController<List<int>>();
      final requests = <http.Request>[];
      final httpClient = _FakeHttpClient((request) async {
        final captured = request as http.Request;
        requests.add(captured);
        if (captured.method == 'GET') {
          scheduleMicrotask(() {
            events.add(utf8.encode('event: endpoint\ndata: $endpoint\n\n'));
          });
          return http.StreamedResponse(
            events.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (type == McpTransportType.http &&
            captured.url.path == '/mcp' &&
            jsonDecode(captured.body)['method'] == 'initialize') {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        expect(captured.url, endpoint);
        expect(captured.headers['Authorization'], 'Bearer test-secret');
        final message = jsonDecode(captured.body) as Map<String, dynamic>;
        if (message['method'] == 'initialize') {
          events.add(utf8.encode(_sseMessage({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': _initializeResult(),
          })));
        } else if (message['method'] == 'tools/list') {
          events.add(utf8.encode(_sseMessage({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': _toolList(),
          })));
        }
        return http.StreamedResponse(const Stream.empty(), 202);
      });
      final profile = _remoteServer(type);
      final client = await _connect(profile, httpClient);

      expect(client.tools.map((tool) => tool.name), ['lookup']);
      expect(requests.any((request) => request.method == 'GET'), isTrue);
      if (type == McpTransportType.http) {
        expect(
          requests.any((request) =>
              request.method == 'POST' && request.url.path == '/mcp'),
          isTrue,
        );
      }
      await client.close();
      await events.close();
    });
  }

  test('rejects remote plaintext HTTP and unsafe endpoints', () async {
    expect(isAllowedMcpEndpoint('http://127.0.0.2:8080/mcp'), isTrue);
    expect(isAllowedMcpEndpoint('http://127.evil.test/mcp'), isFalse);
    expect(isAllowedMcpEndpoint('http://127.999.0.1/mcp'), isFalse);

    final httpClient = _FakeHttpClient((_) async {
      fail('The invalid endpoint must be rejected before making a request.');
    });
    await expectLater(
      McpRemoteTransport.connect(
        _remoteServer(
          McpTransportType.http,
          endpoint: 'http://public.example.test/mcp',
        ),
        httpClient: httpClient,
      ),
      throwsA(isA<McpException>()),
    );
    await expectLater(
      McpRemoteTransport.connect(
        _remoteServer(
          McpTransportType.http,
          endpoint: 'https://user:password@example.test/mcp',
        ),
        httpClient: httpClient,
      ),
      throwsA(isA<McpException>()),
    );
    httpClient.close();
  });

  test('does not serialize remote MCP header values into profile settings', () {
    final profile = _remoteServer(McpTransportType.http);
    final json = profile.toJson();

    expect(json, isNot(contains('headers')));
    expect(json, isNot(contains('test-secret')));
    expect(json['headerNames'], ['Authorization']);
    final restored = McpServerProfile.fromJson(json);
    expect(restored!.headers, isEmpty);
    expect(restored.credentialHeaderNames, ['Authorization']);
  });
}

Future<McpStdioClient> _connect(
  McpServerProfile profile,
  http.Client httpClient,
) =>
    McpStdioClient.connect(
      profile,
      transportFactory: (server) =>
          McpRemoteTransport.connect(server, httpClient: httpClient),
    );

McpServerProfile _remoteServer(
  McpTransportType type, {
  String endpoint = 'https://mcp.example.test/mcp',
}) =>
    McpServerProfile(
      id: 'remote-test',
      name: 'Remote test',
      transport: type,
      endpoint: endpoint,
      headers: const {'Authorization': 'Bearer test-secret'},
    );

Map<String, Object?> _initializeResult() => {
      'protocolVersion': '2025-11-25',
      'serverInfo': {'name': 'Remote test server', 'version': '1.0'},
      'capabilities': {'tools': <String, dynamic>{}},
    };

Map<String, Object?> _toolList() => {
      'tools': [
        {
          'name': 'lookup',
          'description': 'Look up a remote record.',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
            },
          },
        },
      ],
    };

http.StreamedResponse _jsonResponse(
  http.Request request,
  Map<String, Object?> value, {
  Map<String, String> headers = const {},
}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(value))),
      200,
      request: request,
      headers: {'content-type': 'application/json', ...headers},
    );

String _sseMessage(Map<String, Object?> message) =>
    'event: message\ndata: ${jsonEncode(message)}\n\n';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closed) throw StateError('HTTP client is closed.');
    return handler(request);
  }

  @override
  void close() => closed = true;
}
