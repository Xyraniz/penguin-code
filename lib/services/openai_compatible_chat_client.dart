import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models.dart';

class ChatConnectionException implements Exception {
  const ChatConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenAiCompatibleChatClient {
  OpenAiCompatibleChatClient({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void validateProvider(ProviderProfile provider) {
    _completionUri(provider.endpoint);
    if (provider.model.trim().isEmpty) {
      throw const ChatConnectionException('Enter a model identifier.');
    }
  }

  Stream<String> streamCompletion({
    required ProviderProfile provider,
    required List<ChatMessage> history,
    required Future<void> abortTrigger,
  }) async* {
    final uri = _completionUri(provider.endpoint);
    final request = http.AbortableRequest(
      'POST',
      uri,
      abortTrigger: abortTrigger,
    )
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Content-Type'] = 'application/json';
    final apiKey = provider.apiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }
    request.body = jsonEncode({
      'model': provider.model,
      'stream': true,
      'messages': [
        for (final message in history)
          {
            'role': message.role == ChatMessageRole.user ? 'user' : 'assistant',
            'content': message.content,
          },
      ],
    });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(
            const Duration(seconds: 45),
          );
    } on TimeoutException {
      throw const ChatConnectionException(
        'The provider did not respond. Check the endpoint and try again.',
      );
    } on http.ClientException {
      throw const ChatConnectionException(
        'Could not connect to the provider. Check the endpoint and try again.',
      );
    } on SocketException {
      throw const ChatConnectionException(
        'Could not connect to the provider. Check that it is running.',
      );
    } on IOException {
      throw const ChatConnectionException(
        'The provider connection was interrupted. Try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatConnectionException(
        'The provider returned HTTP ${response.statusCode}. Check the model, API key, and endpoint.',
      );
    }

    var receivedText = false;
    final dataLines = <String>[];
    try {
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 90))) {
        if (line.isEmpty) {
          final chunk = _readEvent(dataLines);
          dataLines.clear();
          if (chunk == null) break;
          if (chunk.isNotEmpty) {
            receivedText = true;
            yield chunk;
          }
        } else if (!line.startsWith(':') && line.startsWith('data:')) {
          final value = line.substring(5);
          dataLines.add(value.startsWith(' ') ? value.substring(1) : value);
        }
      }
      final finalChunk = _readEvent(dataLines);
      if (finalChunk != null && finalChunk.isNotEmpty) {
        receivedText = true;
        yield finalChunk;
      }
    } on TimeoutException {
      throw const ChatConnectionException(
        'The provider stopped streaming. Try again.',
      );
    } on FormatException {
      throw const ChatConnectionException(
        'The provider returned an unreadable response. Check that it supports OpenAI-compatible streaming.',
      );
    } on http.ClientException {
      throw const ChatConnectionException(
        'The provider connection was interrupted. Try again.',
      );
    } on IOException {
      throw const ChatConnectionException(
        'The provider connection was interrupted. Try again.',
      );
    }

    if (!receivedText) {
      throw const ChatConnectionException(
        'The provider returned no text. Check the model and try again.',
      );
    }
  }

  String? _readEvent(List<String> dataLines) {
    if (dataLines.isEmpty) return '';
    final data = dataLines.join('\n');
    if (data == '[DONE]') return null;
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid streaming event.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return '';
    }
    final delta = (choices.first as Map)['delta'];
    if (delta is! Map) return '';
    final content = delta['content'];
    return content is String ? content : '';
  }

  Uri _completionUri(String endpoint) {
    final base = Uri.tryParse(endpoint.trim());
    if (base == null || !base.hasAuthority || base.host.isEmpty) {
      throw const ChatConnectionException('Enter a valid provider base URL.');
    }
    if (base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment) {
      throw const ChatConnectionException(
        'The provider URL cannot contain credentials, a query, or a fragment.',
      );
    }
    final loopback = base.host.toLowerCase() == 'localhost' ||
        InternetAddress.tryParse(base.host)?.isLoopback == true;
    if (base.scheme != 'https' && !(base.scheme == 'http' && loopback)) {
      throw const ChatConnectionException(
        'Use HTTPS for remote providers. HTTP is allowed only for localhost.',
      );
    }
    final normalizedPath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final endpointPath = normalizedPath.endsWith('/chat/completions')
        ? normalizedPath
        : '$normalizedPath/chat/completions';
    return base.replace(path: endpointPath);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
