import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/mcp_stdio_client.dart';

void main() {
  group('McpStdioClient', () {
    test('initializes, reads paginated tools, and invokes a tool', () async {
      final transport = _FakeTransport();
      final client = await McpStdioClient.connect(
        _server,
        transportFactory: (_) async => transport,
      );

      expect(
        transport.sent.map((message) => message['method']),
        ['initialize', 'notifications/initialized', 'tools/list', 'tools/list'],
      );
      expect(client.tools.map((tool) => tool.name), ['lookup', 'read_file']);
      expect(client.tools.first.inputSchema['required'], ['query']);
      expect(
        transport.sent.last['params'],
        {'cursor': 'page-two'},
      );

      final result = await client.callTool('lookup', {'query': 'penguin'});

      expect(result, 'Found penguin');
      final call = transport.sent.last;
      expect(call['method'], 'tools/call');
      expect(call['params'], {
        'name': 'lookup',
        'arguments': {'query': 'penguin'},
      });
      await client.close();
      expect(transport.closed, isTrue);
    });

    test('rejects servers that do not advertise the tools capability',
        () async {
      final transport = _FakeTransport(withToolsCapability: false);

      await expectLater(
        McpStdioClient.connect(
          _server,
          transportFactory: (_) async => transport,
        ),
        throwsA(isA<McpException>().having(
          (error) => error.message,
          'message',
          contains('does not provide tools'),
        )),
      );
      expect(transport.closed, isTrue);
      expect(
          transport.sent.map((message) => message['method']), ['initialize']);
    });

    test('keeps long tool output intact for chat-level spill storage',
        () async {
      final transport = _FakeTransport(callOutput: 'x' * 25000);
      final client = await McpStdioClient.connect(
        _server,
        transportFactory: (_) async => transport,
      );

      final result = await client.callTool('lookup', {'query': 'large'});

      expect(result.length, 25000);
      expect(result, startsWith('x'));
      expect(result, endsWith('x'));
      await client.close();
    });
  });

  test('namespaces duplicate server tool names and routes calls by server',
      () async {
    final transport = _FakeTransport(callOutput: 'server result');
    final manager = McpServerManager(
      transportFactory: (_) async => transport,
    );
    await manager.connect(_server.copyWith(enabled: true));

    expect(manager.statusFor(_server.id).state,
        McpServerConnectionState.connected);
    expect(manager.agentTools.map((tool) => tool.functionName), [
      'mcp_tool_00_lookup',
      'mcp_tool_01_read_file',
    ]);
    expect(manager.supportsTool('mcp_tool_00_lookup'), isTrue);
    expect(
      await manager.executeTool('mcp_tool_00_lookup', {'query': 'ok'}),
      'server result',
    );
    expect(
      await manager.executeTool('mcp_tool_99_unknown', const {}),
      contains('disconnected'),
    );
    await manager.close();
  });

  test('withdraws tools when a connected server exits', () async {
    final transport = _FakeTransport();
    final manager = McpServerManager(
      transportFactory: (_) async => transport,
    );
    await manager.connect(_server.copyWith(enabled: true));
    expect(manager.agentTools, isNotEmpty);

    await transport.end();
    await Future<void>.delayed(Duration.zero);

    expect(manager.agentTools, isEmpty);
    expect(
      manager.statusFor(_server.id).state,
      McpServerConnectionState.error,
    );
    await manager.close();
  });

  test('validates persisted MCP server profiles', () {
    final profile = McpServerProfile.fromJson({
      'id': 'server-one',
      'name': 'Filesystem',
      'command': 'node',
      'arguments': ['server.js', '--stdio'],
      'enabled': true,
    });

    expect(profile, isNotNull);
    expect(profile!.arguments, ['server.js', '--stdio']);
    expect(profile.enabled, isTrue);
    expect(
      McpServerProfile.fromJson({
        'id': 'bad',
        'name': 'Invalid',
        'command': 'node',
        'arguments': [1],
      }),
      isNull,
    );
  });
}

const _server = McpServerProfile(
  id: 'test-server',
  name: 'Test server',
  command: 'test-mcp',
);

class _FakeTransport implements McpStdioTransport {
  _FakeTransport({
    this.withToolsCapability = true,
    this.callOutput = 'Found penguin',
  });

  final bool withToolsCapability;
  final String callOutput;
  final _lines = StreamController<String>();
  final List<Map<String, dynamic>> sent = [];
  bool closed = false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  void sendLine(String line) {
    final request = jsonDecode(line) as Map<String, dynamic>;
    sent.add(request);
    final method = request['method'];
    if (method == 'notifications/initialized') return;

    Map<String, dynamic> result;
    if (method == 'initialize') {
      result = {
        'protocolVersion': '2025-11-25',
        'serverInfo': {'name': 'Fake', 'version': '1.0'},
        'capabilities': {
          if (withToolsCapability) 'tools': <String, dynamic>{},
        },
      };
    } else if (method == 'tools/list') {
      final hasCursor = (request['params'] as Map)['cursor'] != null;
      result = hasCursor
          ? {
              'tools': [
                {
                  'name': 'read_file',
                  'description': 'Read a file.',
                  'inputSchema': {
                    'type': 'object',
                    'properties': {
                      'path': {'type': 'string'}
                    },
                  },
                },
              ],
            }
          : {
              'tools': [
                {
                  'name': 'lookup',
                  'description': 'Find a record.',
                  'inputSchema': {
                    'type': 'object',
                    'properties': {
                      'query': {'type': 'string'}
                    },
                    'required': ['query'],
                  },
                },
              ],
              'nextCursor': 'page-two',
            };
    } else if (method == 'tools/call') {
      result = {
        'content': [
          {'type': 'text', 'text': callOutput},
        ],
        'isError': false,
      };
    } else {
      return;
    }
    _lines.add(
        jsonEncode({'jsonrpc': '2.0', 'id': request['id'], 'result': result}));
  }

  @override
  Future<void> close() async {
    closed = true;
    await _lines.close();
  }

  Future<void> end() => _lines.close();
}
