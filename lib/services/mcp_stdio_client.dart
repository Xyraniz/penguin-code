import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';

const _mcpProtocolVersion = '2025-11-25';

class McpException implements Exception {
  const McpException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class McpStdioTransport {
  Stream<String> get lines;

  void sendLine(String line);

  Future<void> close();
}

typedef McpTransportFactory = Future<McpStdioTransport> Function(
  McpServerProfile server,
);

class _ProcessMcpStdioTransport implements McpStdioTransport {
  _ProcessMcpStdioTransport(this._process) {
    _process.stderr.listen((_) {});
    _process.stdout.listen(
      _onBytes,
      onError: (Object error, StackTrace stack) {
        if (!_closed) _lines.addError(error, stack);
      },
      onDone: () {
        if (_lineBytes.isNotEmpty && !_closed) {
          _lines.addError(
              const McpException('The MCP server ended mid-message.'));
        }
        if (!_closed) _lines.close();
      },
      cancelOnError: false,
    );
  }

  final Process _process;
  final StreamController<String> _lines = StreamController<String>();
  final List<int> _lineBytes = [];
  bool _closed = false;

  static Future<_ProcessMcpStdioTransport> start(
    McpServerProfile server,
  ) async {
    if (server.command.trim().isEmpty) {
      throw const McpException('Enter a command for this MCP server.');
    }
    if (server.name.trim().isEmpty ||
        server.name.trim().length > 80 ||
        server.command.length > 1024 ||
        server.command.contains('\n') ||
        server.command.contains('\r') ||
        server.arguments.length > 64 ||
        server.arguments.fold<int>(0, (total, value) => total + value.length) >
            16384) {
      throw const McpException('This MCP server configuration is too large.');
    }
    try {
      final process = await Process.start(
        server.command,
        server.arguments,
        runInShell: false,
        includeParentEnvironment: true,
      );
      return _ProcessMcpStdioTransport(process);
    } on ProcessException catch (error) {
      throw McpException('Could not start the MCP server: ${error.message}');
    }
  }

  @override
  Stream<String> get lines => _lines.stream;

  void _onBytes(List<int> bytes) {
    for (final byte in bytes) {
      if (byte == 0x0A) {
        if (_lineBytes.isNotEmpty && _lineBytes.last == 0x0D) {
          _lineBytes.removeLast();
        }
        try {
          _lines.add(utf8.decode(_lineBytes, allowMalformed: false));
        } on FormatException {
          _lines.addError(
              const McpException('The MCP server sent invalid UTF-8.'));
        }
        _lineBytes.clear();
      } else {
        _lineBytes.add(byte);
        if (_lineBytes.length > McpStdioClient.maxMessageBytes) {
          _lines.addError(const McpException(
            'The MCP server sent a message larger than the 1 MiB limit.',
          ));
          _lineBytes.clear();
          _closed = true;
          _process.kill();
          unawaited(_lines.close());
          return;
        }
      }
    }
  }

  @override
  void sendLine(String line) {
    if (_closed || line.contains('\n') || line.contains('\r')) {
      throw const McpException('The MCP server connection is unavailable.');
    }
    _process.stdin.writeln(line);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _process.stdin.close();
      await _process.exitCode.timeout(const Duration(milliseconds: 750));
    } on TimeoutException {
      _process.kill();
      await _process.exitCode.timeout(const Duration(seconds: 2)).catchError(
            (_) => -1,
          );
    } on IOException {
      _process.kill();
    }
    if (!_lines.isClosed) await _lines.close();
  }
}

class McpRemoteTool {
  const McpRemoteTool({
    required this.serverId,
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String serverId;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

class McpAgentToolDefinition {
  const McpAgentToolDefinition({
    required this.functionName,
    required this.tool,
  });

  final String functionName;
  final McpRemoteTool tool;

  Map<String, Object?> toOpenAiTool() => {
        'type': 'function',
        'function': {
          'name': functionName,
          'description':
              'MCP server "${tool.serverName}" tool "${tool.name}". ${tool.description}',
          'parameters': tool.inputSchema,
        },
      };
}

class McpStdioClient {
  McpStdioClient._(this._transport, this.server);

  static const maxMessageBytes = 1024 * 1024;
  static const maxToolArgumentBytes = 64 * 1024;
  static const maxToolOutputCharacters = 24000;
  static const maxToolsPerServer = 48;

  final McpStdioTransport _transport;
  final McpServerProfile server;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  late final StreamSubscription<String> _subscription;
  int _nextRequestId = 0;
  bool _closed = false;
  bool _disposed = false;
  List<McpRemoteTool> _tools = const [];
  void Function()? onToolsChanged;
  void Function(Object error)? onDisconnected;

  List<McpRemoteTool> get tools => _tools;

  static Future<McpStdioClient> connect(
    McpServerProfile server, {
    McpTransportFactory? transportFactory,
  }) async {
    final transport = await (transportFactory ?? _startProcess)(server);
    final client = McpStdioClient._(transport, server);
    client._subscription = transport.lines.listen(
      client._onLine,
      onError: (Object error, StackTrace stack) =>
          client._markDisconnected(error),
      onDone: () => client._markDisconnected(
        const McpException('The MCP server process ended.'),
      ),
    );
    try {
      await client._initialize();
      await client.refreshTools();
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  static Future<McpStdioTransport> _startProcess(
    McpServerProfile server,
  ) async =>
      _ProcessMcpStdioTransport.start(server);

  Future<void> _initialize() async {
    final result = await _request(
        'initialize',
        {
          'protocolVersion': _mcpProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': {
            'name': 'Penguin Code',
            'version': '0.1.0',
          },
        },
        timeout: const Duration(seconds: 12));
    if (result['protocolVersion'] is! String || result['serverInfo'] is! Map) {
      throw const McpException('The MCP server returned an invalid handshake.');
    }
    final capabilities = result['capabilities'];
    if (capabilities is! Map || capabilities['tools'] is! Map) {
      throw const McpException('This MCP server does not provide tools.');
    }
    _send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  Future<List<McpRemoteTool>> refreshTools() async {
    final discovered = <McpRemoteTool>[];
    final cursors = <String>{};
    String? cursor;
    do {
      if (discovered.length >= maxToolsPerServer) break;
      final params = <String, Object?>{if (cursor != null) 'cursor': cursor};
      final result = await _request('tools/list', params);
      final items = result['tools'];
      if (items is! List) {
        throw const McpException(
            'The MCP server returned an invalid tool list.');
      }
      for (final item in items) {
        if (discovered.length >= maxToolsPerServer) break;
        if (item is! Map ||
            item['name'] is! String ||
            (item['name'] as String).isEmpty ||
            item['inputSchema'] is! Map) {
          continue;
        }
        final schema = Map<String, dynamic>.from(item['inputSchema'] as Map);
        if (schema['type'] != 'object') continue;
        if (utf8.encode(jsonEncode(schema)).length > maxToolArgumentBytes) {
          continue;
        }
        final toolName = item['name'] as String;
        if (discovered.any((tool) => tool.name == toolName)) continue;
        discovered.add(McpRemoteTool(
          serverId: server.id,
          serverName: server.name,
          name: toolName,
          description: (item['description'] is String
                  ? item['description'] as String
                  : '')
              .substring(
            0,
            (item['description'] is String
                    ? (item['description'] as String).length
                    : 0)
                .clamp(0, 4000)
                .toInt(),
          ),
          inputSchema: schema,
        ));
      }
      final nextCursor = result['nextCursor'];
      if (nextCursor is! String || nextCursor.isEmpty) {
        cursor = null;
      } else if (nextCursor.length > 1024 || !cursors.add(nextCursor)) {
        throw const McpException(
            'The MCP server returned an invalid page cursor.');
      } else {
        cursor = nextCursor;
      }
    } while (cursor != null);
    _tools = List.unmodifiable(discovered);
    return _tools;
  }

  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    if (!_tools.any((tool) => tool.name == name)) {
      return 'Tool error: this MCP tool is no longer available.';
    }
    if (utf8.encode(jsonEncode(arguments)).length > maxToolArgumentBytes) {
      return 'Tool error: MCP tool arguments exceed the 64 KiB limit.';
    }
    try {
      final result = await _request(
          'tools/call',
          {
            'name': name,
            'arguments': arguments,
          },
          timeout: const Duration(seconds: 30));
      final text = _toolResultText(result);
      final bounded = text.length > maxToolOutputCharacters
          ? '${text.substring(0, maxToolOutputCharacters)}\n[Output truncated at 24,000 characters.]'
          : text;
      return result['isError'] == true ? 'Tool error: $bounded' : bounded;
    } on McpException catch (error) {
      return 'Tool error: ${error.message}';
    } on TimeoutException {
      return 'Tool error: the MCP tool timed out after 30 seconds.';
    }
  }

  String _toolResultText(Map<String, dynamic> result) {
    final content = result['content'];
    final parts = <String>[];
    if (content is List) {
      for (final block in content) {
        if (block is! Map) continue;
        if (block['type'] == 'text' && block['text'] is String) {
          parts.add(block['text'] as String);
        } else if (block['type'] == 'resource_link') {
          parts.add('Resource: ${block['name'] ?? ''} ${block['uri'] ?? ''}');
        } else if (block['type'] == 'image') {
          parts.add('[Image result omitted.]');
        } else if (block['type'] == 'audio') {
          parts.add('[Audio result omitted.]');
        }
      }
    }
    if (parts.isEmpty && result['structuredContent'] != null) {
      parts.add(jsonEncode(result['structuredContent']));
    }
    return parts.join('\n\n').isEmpty
        ? 'The MCP tool completed.'
        : parts.join('\n\n');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, Object?> params, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_closed) throw const McpException('The MCP server is disconnected.');
    final id = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      });
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw McpException('The MCP server timed out while handling $method.');
    } finally {
      _pending.remove(id);
    }
  }

  void _send(Map<String, Object?> message) {
    if (_closed) throw const McpException('The MCP server is disconnected.');
    final line = jsonEncode(message);
    if (utf8.encode(line).length > maxMessageBytes) {
      throw const McpException('The MCP request exceeds the 1 MiB limit.');
    }
    _transport.sendLine(line);
  }

  void _onLine(String line) {
    if (line.isEmpty || line.length > maxMessageBytes) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _failPending(const McpException('The MCP server sent invalid JSON.'));
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded['jsonrpc'] != '2.0') return;
    final id = decoded['id'];
    if (id is int) {
      final pending = _pending[id];
      if (pending == null || pending.isCompleted) return;
      final error = decoded['error'];
      if (error is Map) {
        final message = error['message'] is String
            ? (error['message'] as String).substring(
                0,
                (error['message'] as String).length.clamp(0, 2000).toInt(),
              )
            : 'Unknown MCP protocol error.';
        pending.completeError(McpException(message));
        return;
      }
      final result = decoded['result'];
      if (result is Map) {
        pending.complete(Map<String, dynamic>.from(result));
      } else {
        pending.completeError(
          const McpException('The MCP server returned an invalid response.'),
        );
      }
      return;
    }
    if (decoded['method'] is String && id != null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32601, 'message': 'Client request is unsupported.'},
      });
    } else if (decoded['method'] == 'notifications/tools/list_changed') {
      final callback = onToolsChanged;
      if (callback != null) callback();
    }
  }

  void _failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  void _markDisconnected(Object error) {
    if (_closed) return;
    _closed = true;
    _failPending(error);
    onDisconnected?.call(error);
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _closed = true;
    _failPending(const McpException('The MCP server was disconnected.'));
    await _subscription.cancel();
    await _transport.close();
  }
}

enum McpServerConnectionState { disconnected, connecting, connected, error }

class McpServerStatus {
  const McpServerStatus({
    required this.state,
    this.error,
    this.toolCount = 0,
  });

  final McpServerConnectionState state;
  final String? error;
  final int toolCount;
}

class _McpToolRoute {
  const _McpToolRoute(this.client, this.tool);

  final McpStdioClient client;
  final McpRemoteTool tool;
}

class McpServerManager {
  McpServerManager({this.onChanged, this.transportFactory});

  static const maxConnectedServers = 8;
  static const maxExposedTools = 48;
  static const maxToolSchemaBytes = 128 * 1024;

  final void Function()? onChanged;
  final McpTransportFactory? transportFactory;
  final Map<String, McpStdioClient> _clients = {};
  final Map<String, McpServerStatus> _statuses = {};
  final Map<String, int> _connectionVersions = {};
  final Set<String> _connecting = {};
  Map<String, _McpToolRoute> _routes = {};
  List<McpAgentToolDefinition> _agentTools = const [];

  List<McpAgentToolDefinition> get agentTools => _agentTools;

  McpServerStatus statusFor(String serverId) =>
      _statuses[serverId] ??
      const McpServerStatus(state: McpServerConnectionState.disconnected);

  bool supportsTool(String functionName) => _routes.containsKey(functionName);

  Future<void> connect(McpServerProfile server) async {
    if (_clients.length + _connecting.length >= maxConnectedServers &&
        !_clients.containsKey(server.id)) {
      _statuses[server.id] = const McpServerStatus(
        state: McpServerConnectionState.error,
        error: 'Penguin Code allows up to eight connected MCP servers.',
      );
      onChanged?.call();
      return;
    }
    await disconnect(server.id);
    final version = (_connectionVersions[server.id] ?? 0) + 1;
    _connectionVersions[server.id] = version;
    _connecting.add(server.id);
    _statuses[server.id] = const McpServerStatus(
      state: McpServerConnectionState.connecting,
    );
    onChanged?.call();
    try {
      final client = await McpStdioClient.connect(
        server,
        transportFactory: transportFactory,
      );
      if (_connectionVersions[server.id] != version) {
        await client.close();
        return;
      }
      client.onDisconnected =
          (error) => unawaited(_handleDisconnected(server.id, client, error));
      client.onToolsChanged =
          () => unawaited(_refreshAfterNotification(server.id));
      _clients[server.id] = client;
      _statuses[server.id] = McpServerStatus(
        state: McpServerConnectionState.connected,
        toolCount: client.tools.length,
      );
      _rebuildAgentTools();
    } catch (error) {
      if (_connectionVersions[server.id] == version) {
        _statuses[server.id] = McpServerStatus(
          state: McpServerConnectionState.error,
          error: error
              .toString()
              .substring(0, error.toString().length.clamp(0, 800).toInt()),
        );
      }
    } finally {
      if (_connectionVersions[server.id] == version) {
        _connecting.remove(server.id);
      }
    }
    onChanged?.call();
  }

  Future<void> _handleDisconnected(
    String serverId,
    McpStdioClient client,
    Object error,
  ) async {
    if (!identical(_clients[serverId], client)) return;
    _clients.remove(serverId);
    _statuses[serverId] = McpServerStatus(
      state: McpServerConnectionState.error,
      error: error.toString().substring(
            0,
            error.toString().length.clamp(0, 800).toInt(),
          ),
    );
    _rebuildAgentTools();
    onChanged?.call();
    await client.close();
  }

  Future<void> _refreshAfterNotification(String serverId) async {
    final client = _clients[serverId];
    if (client == null) return;
    try {
      await client.refreshTools();
      _statuses[serverId] = McpServerStatus(
        state: McpServerConnectionState.connected,
        toolCount: client.tools.length,
      );
      _rebuildAgentTools();
      onChanged?.call();
    } catch (error) {
      _statuses[serverId] = McpServerStatus(
        state: McpServerConnectionState.error,
        error: error.toString(),
      );
      onChanged?.call();
    }
  }

  Future<void> refresh(String serverId) => _refreshAfterNotification(serverId);

  Future<void> disconnect(String serverId) async {
    _connectionVersions[serverId] = (_connectionVersions[serverId] ?? 0) + 1;
    _connecting.remove(serverId);
    final client = _clients.remove(serverId);
    if (client != null) await client.close();
    _statuses[serverId] = const McpServerStatus(
      state: McpServerConnectionState.disconnected,
    );
    _rebuildAgentTools();
    onChanged?.call();
  }

  Future<String> executeTool(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    final route = _routes[functionName];
    if (route == null || !_clients.containsKey(route.tool.serverId)) {
      return 'Tool error: this MCP server is disconnected.';
    }
    return route.client.callTool(route.tool.name, arguments);
  }

  void _rebuildAgentTools() {
    final definitions = <McpAgentToolDefinition>[];
    final routes = <String, _McpToolRoute>{};
    var index = 0;
    var schemaBytes = 0;
    for (final client in _clients.values) {
      for (final tool in client.tools) {
        if (definitions.length >= maxExposedTools) break;
        final suffix = tool.name
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
            .replaceAll(RegExp(r'_+'), '_');
        final toolIndex = index++;
        final functionName =
            'mcp_tool_${toolIndex.toString().padLeft(2, '0')}_${suffix.substring(0, suffix.length.clamp(0, 48).toInt())}';
        final definition = McpAgentToolDefinition(
          functionName: functionName,
          tool: tool,
        );
        final definitionBytes =
            utf8.encode(jsonEncode(definition.toOpenAiTool())).length;
        if (schemaBytes + definitionBytes > maxToolSchemaBytes) continue;
        definitions.add(definition);
        routes[functionName] = _McpToolRoute(client, tool);
        schemaBytes += definitionBytes;
      }
    }
    _agentTools = List.unmodifiable(definitions);
    _routes = routes;
  }

  Future<void> close() async {
    for (final serverId in {..._clients.keys, ..._connecting}) {
      _connectionVersions[serverId] = (_connectionVersions[serverId] ?? 0) + 1;
    }
    _connecting.clear();
    final clients = _clients.values.toList(growable: false);
    _clients.clear();
    _routes = {};
    _agentTools = const [];
    await Future.wait(clients.map((client) => client.close()));
  }
}
