import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models.dart';

abstract interface class McpCredentialStore {
  Future<Map<String, String>> readHeaders(String serverId);

  Future<void> writeHeaders(String serverId, Map<String, String> headers);

  Future<void> deleteHeaders(String serverId);
}

class SecureMcpCredentialStore implements McpCredentialStore {
  SecureMcpCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String serverId) => 'penguin_code.mcp_headers.$serverId';

  @override
  Future<Map<String, String>> readHeaders(String serverId) async {
    final saved = await _storage.read(key: _key(serverId));
    if (saved == null || saved.isEmpty || saved.length > 32768) {
      return const {};
    }
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map ||
          decoded.length > 32 ||
          decoded.entries.any((entry) =>
              entry.key is! String ||
              !isValidMcpHeaderName(entry.key as String) ||
              entry.value is! String ||
              (entry.value as String).contains('\n') ||
              (entry.value as String).contains('\r'))) {
        return const {};
      }
      return Map.unmodifiable(decoded.cast<String, String>());
    } on FormatException {
      return const {};
    }
  }

  @override
  Future<void> writeHeaders(
    String serverId,
    Map<String, String> headers,
  ) async {
    if (headers.isEmpty) {
      await deleteHeaders(serverId);
      return;
    }
    if (headers.length > 32 ||
        headers.entries.any((entry) =>
            !isValidMcpHeaderName(entry.key) ||
            entry.value.contains('\n') ||
            entry.value.contains('\r')) ||
        utf8.encode(jsonEncode(headers)).length > 16384) {
      throw const FormatException(
          'MCP request headers are invalid or too large.');
    }
    await _storage.write(key: _key(serverId), value: jsonEncode(headers));
  }

  @override
  Future<void> deleteHeaders(String serverId) =>
      _storage.delete(key: _key(serverId));
}

class MemoryMcpCredentialStore implements McpCredentialStore {
  final Map<String, Map<String, String>> _headers = {};

  @override
  Future<Map<String, String>> readHeaders(String serverId) async =>
      Map.unmodifiable(_headers[serverId] ?? const {});

  @override
  Future<void> writeHeaders(
    String serverId,
    Map<String, String> headers,
  ) async {
    if (headers.isEmpty) {
      _headers.remove(serverId);
    } else {
      _headers[serverId] = Map.unmodifiable(headers);
    }
  }

  @override
  Future<void> deleteHeaders(String serverId) async {
    _headers.remove(serverId);
  }
}
