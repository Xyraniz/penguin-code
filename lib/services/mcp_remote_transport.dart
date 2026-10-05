import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'mcp_transport.dart';

class McpRemoteTransport implements McpTransport {
  McpRemoteTransport._(
    this.server, {
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _endpoint = Uri.parse(server.endpoint);

  static const _maxResponseBytes = mcpMaxMessageBytes;
  static const _protocolVersion = '2025-11-25';

  final McpServerProfile server;
  final http.Client _httpClient;
  final Uri _endpoint;
  final StreamController<String> _lines = StreamController<String>();
  final Completer<Uri> _legacyEndpoint = Completer<Uri>();
  StreamSubscription<String>? _legacySseSubscription;
  String? _sessionId;
  String? _negotiatedProtocolVersion;
  bool _usingLegacySse = false;
  bool _closed = false;

  @override
  Stream<String> get lines => _lines.stream;

  static Future<McpRemoteTransport> connect(
    McpServerProfile server, {
    http.Client? httpClient,
  }) async {
    if (server.transport == McpTransportType.stdio) {
      throw const McpException('Choose HTTP or SSE for a remote MCP server.');
    }
    if (!isAllowedMcpEndpoint(server.endpoint)) {
      throw const McpException(
        'Use an HTTPS MCP endpoint. Plain HTTP is allowed only for loopback addresses.',
      );
    }
    _validateHeaders(server.headers);
    final transport = McpRemoteTransport._(server, httpClient: httpClient);
    if (server.transport == McpTransportType.sse) {
      try {
        transport._usingLegacySse = true;
        await transport._openLegacySse();
      } catch (_) {
        await transport.close();
        rethrow;
      }
    }
    return transport;
  }

  static void _validateHeaders(Map<String, String> headers) {
    if (headers.length > 32 ||
        headers.entries.any((entry) =>
            !isValidMcpHeaderName(entry.key) ||
            entry.value.contains('\n') ||
            entry.value.contains('\r')) ||
        utf8.encode(jsonEncode(headers)).length > 16384) {
      throw const McpException(
        'MCP request headers are invalid or exceed the 16 KiB limit.',
      );
    }
  }

  @override
  void sendLine(String line) {
    if (_closed || line.length > mcpMaxMessageBytes) {
      throw const McpException('The MCP server connection is unavailable.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      throw const McpException('The MCP request is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic> || decoded['jsonrpc'] != '2.0') {
      throw const McpException('The MCP request is not valid JSON-RPC.');
    }
    unawaited(_dispatch(line, decoded));
  }

  Future<void> _dispatch(
    String line,
    Map<String, dynamic> message,
  ) async {
    try {
      if (_usingLegacySse) {
        await _postLegacyMessage(line, message);
      } else {
        await _postStreamableMessage(line, message);
      }
    } catch (error) {
      if (!_closed) {
        _lines.addError(
          error is McpException
              ? error
              : const McpException('The remote MCP server request failed.'),
        );
      }
    }
  }

  Future<void> _postStreamableMessage(
    String line,
    Map<String, dynamic> message,
  ) async {
    final response = await _sendPost(
      _endpoint,
      line,
      accept: 'application/json, text/event-stream',
      protocolVersion: _negotiatedProtocolVersion,
      sessionId: _sessionId,
    );
    if (_isInitialize(message) &&
        const {400, 404, 405}.contains(response.statusCode)) {
      await _discard(response.stream);
      await _openLegacySse();
      _usingLegacySse = true;
      await _postLegacyMessage(line, message);
      return;
    }
    if (_isInitialize(message)) {
      _sessionId = _responseHeader(response, 'mcp-session-id');
    }
    await _consumeResponse(response, message);
  }

  Future<void> _postLegacyMessage(
    String line,
    Map<String, dynamic> message,
  ) async {
    final endpoint = await _legacyEndpoint.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw const McpException(
        'The MCP SSE server did not provide a message endpoint.',
      ),
    );
    final response = await _sendPost(
      endpoint,
      line,
      accept: 'application/json, text/event-stream',
      protocolVersion: _negotiatedProtocolVersion,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _discard(response.stream);
      throw McpException(
        'The MCP SSE server returned HTTP ${response.statusCode}.',
      );
    }
    if (response.statusCode == 202) return;
    final contentType = _responseHeader(response, 'content-type') ?? '';
    if (contentType.toLowerCase().contains('text/event-stream')) {
      await _consumeSse(response.stream);
      return;
    }
    if (contentType.toLowerCase().contains('application/json')) {
      await _emitJsonBody(response.stream);
      return;
    }
    final bytes = await _readBounded(response.stream);
    if (bytes.isNotEmpty) {
      throw const McpException(
        'The MCP SSE server returned an unsupported response type.',
      );
    }
    if (_isRequest(message)) {
      throw const McpException(
        'The MCP SSE server accepted the request without returning its response stream.',
      );
    }
  }

  Future<http.StreamedResponse> _sendPost(
    Uri endpoint,
    String body, {
    required String accept,
    String? protocolVersion,
    String? sessionId,
  }) async {
    if (_closed) throw const McpException('The MCP server is disconnected.');
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll(server.headers)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = accept
      ..body = body;
    if (protocolVersion != null) {
      request.headers['MCP-Protocol-Version'] = protocolVersion;
    }
    if (sessionId != null) request.headers['Mcp-Session-Id'] = sessionId;
    try {
      return await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const McpException('The remote MCP server timed out.');
    } on http.ClientException {
      throw const McpException('Could not reach the remote MCP server.');
    }
  }

  Future<void> _consumeResponse(
    http.StreamedResponse response,
    Map<String, dynamic> requestMessage,
  ) async {
    if (response.statusCode == 202 && !_isRequest(requestMessage)) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _discard(response.stream);
      throw McpException(
        'The remote MCP server returned HTTP ${response.statusCode}.',
      );
    }
    final contentType = _responseHeader(response, 'content-type') ?? '';
    if (contentType.toLowerCase().contains('text/event-stream')) {
      await _consumeSse(response.stream);
      return;
    }
    if (contentType.toLowerCase().contains('application/json')) {
      await _emitJsonBody(response.stream);
      return;
    }
    await _discard(response.stream);
    throw const McpException(
      'The remote MCP server returned an unsupported response type.',
    );
  }

  Future<void> _emitJsonBody(Stream<List<int>> stream) async {
    final bytes = await _readBounded(stream);
    if (bytes.isEmpty) {
      throw const McpException(
          'The remote MCP server returned an empty response.');
    }
    final decoded = _decodeJsonMessage(bytes);
    _recordNegotiatedVersion(decoded);
    _lines.add(utf8.decode(bytes, allowMalformed: false));
  }

  Future<void> _consumeSse(Stream<List<int>> stream) async {
    final parser = _SseParser((event, data) {
      if (data.isEmpty || event == 'endpoint') return;
      final decoded = _decodeJsonMessage(utf8.encode(data));
      _recordNegotiatedVersion(decoded);
      _lines.add(data);
    });
    try {
      await for (final line in stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 60))) {
        parser.addLine(line);
      }
      parser.flush();
    } on TimeoutException {
      throw const McpException('The remote MCP event stream timed out.');
    } on FormatException {
      throw const McpException('The remote MCP server sent invalid UTF-8.');
    }
  }

  Future<void> _openLegacySse() async {
    if (!_legacyEndpoint.isCompleted) {
      final request = http.Request('GET', _endpoint)
        ..followRedirects = false
        ..headers.addAll(server.headers)
        ..headers['Accept'] = 'text/event-stream';
      if (_negotiatedProtocolVersion != null) {
        request.headers['MCP-Protocol-Version'] = _negotiatedProtocolVersion!;
      }
      final http.StreamedResponse response;
      try {
        response = await _httpClient
            .send(request)
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        throw const McpException(
            'The MCP SSE server timed out while connecting.');
      } on http.ClientException {
        throw const McpException('Could not reach the remote MCP SSE server.');
      }
      if (response.statusCode != 200 ||
          !(_responseHeader(response, 'content-type') ?? '')
              .toLowerCase()
              .contains('text/event-stream')) {
        await _discard(response.stream);
        throw McpException(
          'The MCP SSE server did not open an event stream (HTTP ${response.statusCode}).',
        );
      }
      final parser = _SseParser(_handleLegacyEvent);
      _legacySseSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          try {
            parser.addLine(line);
          } on Object catch (error) {
            if (!_legacyEndpoint.isCompleted) {
              _legacyEndpoint.completeError(error);
            } else if (!_closed) {
              _lines.addError(error);
            }
            unawaited(_legacySseSubscription?.cancel());
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!_closed && !_legacyEndpoint.isCompleted) {
            _legacyEndpoint.completeError(
              const McpException('The MCP SSE connection failed.'),
            );
          } else if (!_closed) {
            _lines.addError(
              const McpException('The MCP SSE connection was interrupted.'),
            );
          }
        },
        onDone: () {
          parser.flush();
          if (!_closed && !_legacyEndpoint.isCompleted) {
            _legacyEndpoint.completeError(
              const McpException(
                  'The MCP SSE server closed before providing its message endpoint.'),
            );
          } else if (!_closed) {
            _lines.addError(
              const McpException('The MCP SSE connection was closed.'),
            );
          }
        },
        cancelOnError: false,
      );
      await _legacyEndpoint.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw const McpException(
          'The MCP SSE server did not provide a message endpoint.',
        ),
      );
    }
  }

  void _handleLegacyEvent(String event, String data) {
    if (event == 'endpoint') {
      if (_legacyEndpoint.isCompleted) return;
      final endpoint = _resolveLegacyEndpoint(data);
      _legacyEndpoint.complete(endpoint);
      return;
    }
    if (data.isEmpty) return;
    final decoded = _decodeJsonMessage(utf8.encode(data));
    _recordNegotiatedVersion(decoded);
    _lines.add(data);
  }

  Uri _resolveLegacyEndpoint(String value) {
    final endpoint = _endpoint.resolve(value.trim());
    if (value.trim().isEmpty ||
        value.length > 2048 ||
        endpoint.scheme != _endpoint.scheme ||
        endpoint.host.toLowerCase() != _endpoint.host.toLowerCase() ||
        endpoint.port != _endpoint.port ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      throw const McpException(
        'The MCP SSE server provided an unsafe message endpoint.',
      );
    }
    return endpoint;
  }

  Map<String, dynamic> _decodeJsonMessage(List<int> bytes) {
    if (bytes.length > mcpMaxMessageBytes) {
      throw const McpException('The MCP response exceeds the 1 MiB limit.');
    }
    final Object? value;
    try {
      value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      throw const McpException('The remote MCP server sent invalid JSON.');
    }
    if (value is! Map<String, dynamic> || value['jsonrpc'] != '2.0') {
      throw const McpException('The remote MCP server sent invalid JSON-RPC.');
    }
    return value;
  }

  void _recordNegotiatedVersion(Map<String, dynamic> message) {
    final result = message['result'];
    if (result is Map && result['protocolVersion'] is String) {
      final version = result['protocolVersion'] as String;
      if (version.length <= 64) _negotiatedProtocolVersion = version;
    }
  }

  static String? _responseHeader(
    http.StreamedResponse response,
    String name,
  ) {
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  static bool _isInitialize(Map<String, dynamic> message) =>
      message['method'] == 'initialize';

  static bool _isRequest(Map<String, dynamic> message) =>
      message['id'] != null && message['method'] is String;

  Future<List<int>> _readBounded(Stream<List<int>> stream) async {
    final bytes = <int>[];
    try {
      await for (final chunk in stream.timeout(const Duration(seconds: 45))) {
        if (bytes.length + chunk.length > _maxResponseBytes) {
          throw const McpException('The MCP response exceeds the 1 MiB limit.');
        }
        bytes.addAll(chunk);
      }
    } on FormatException {
      throw const McpException('The remote MCP server sent invalid data.');
    } on TimeoutException {
      throw const McpException('The remote MCP server response timed out.');
    }
    return bytes;
  }

  Future<void> _discard(Stream<List<int>> stream) async {
    await stream.listen((_) {}).cancel();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _legacySseSubscription?.cancel();
    if (_sessionId != null && server.transport == McpTransportType.http) {
      final request = http.Request('DELETE', _endpoint)
        ..followRedirects = false
        ..headers.addAll(server.headers)
        ..headers['Mcp-Session-Id'] = _sessionId!
        ..headers['MCP-Protocol-Version'] =
            _negotiatedProtocolVersion ?? _protocolVersion;
      try {
        final response =
            await _httpClient.send(request).timeout(const Duration(seconds: 2));
        await _discard(response.stream);
      } on Object {
        // The remote server may already have expired or closed the session.
      }
    }
    _httpClient.close();
    if (!_lines.isClosed) await _lines.close();
  }
}

class _SseParser {
  _SseParser(this.onEvent);

  final void Function(String event, String data) onEvent;
  String? _event;
  final StringBuffer _data = StringBuffer();
  int _dataLength = 0;

  void addLine(String line) {
    if (line.isEmpty) {
      flush();
      return;
    }
    if (line.startsWith(':')) return;
    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      _dataLength += value.length + 1;
      if (_dataLength > mcpMaxMessageBytes) {
        throw const McpException('The MCP SSE event exceeds the 1 MiB limit.');
      }
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(value);
    }
  }

  void flush() {
    if (_data.isEmpty && _event == null) return;
    onEvent(_event ?? 'message', _data.toString());
    _event = null;
    _data.clear();
    _dataLength = 0;
  }
}
