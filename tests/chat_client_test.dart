import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/openai_compatible_chat_client.dart';

void main() {
  group('OpenAiCompatibleChatClient', () {
    test('sends chat history and decodes streamed SSE across byte chunks',
        () async {
      late http.BaseRequest sentRequest;
      final payload = [
        _event({
          'choices': [
            {
              'delta': {'role': 'assistant'}
            }
          ]
        }),
        _event({
          'choices': [
            {
              'delta': {'content': 'Hi 🐧'}
            }
          ]
        }),
        'data: [DONE]\n\n',
      ].join();
      final bytes = utf8.encode(payload);
      final emojiByte = bytes.indexOf(0xF0);
      final fake = _FakeClient((request) async {
        sentRequest = request;
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            bytes.sublist(0, emojiByte + 2),
            bytes.sublist(emojiByte + 2),
          ]),
          200,
        );
      });
      final client = OpenAiCompatibleChatClient(client: fake);
      final chunks = await client
          .streamCompletion(
            provider: _provider(endpoint: 'https://api.example.test/v1/'),
            history: const [
              ChatMessage(
                id: 'user-1',
                role: ChatMessageRole.user,
                content: 'Say hello',
                status: ChatMessageStatus.complete,
              ),
              ChatMessage(
                id: 'assistant-1',
                role: ChatMessageRole.assistant,
                content: 'Previous answer',
                status: ChatMessageStatus.complete,
              ),
            ],
            abortTrigger: Completer<void>().future,
          )
          .toList();

      expect(chunks.join(), 'Hi 🐧');
      expect(sentRequest.url.toString(),
          'https://api.example.test/v1/chat/completions');
      expect(sentRequest.method, 'POST');
      expect(sentRequest.headers['authorization'], 'Bearer test-secret');
      final body = jsonDecode((sentRequest as http.Request).body)
          as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      expect(body['stream'], isTrue);
      expect(body['messages'], [
        {'role': 'user', 'content': 'Say hello'},
        {'role': 'assistant', 'content': 'Previous answer'},
      ]);
    });

    test('allows local HTTP providers and does not require an API key',
        () async {
      late http.BaseRequest sentRequest;
      final fake = _FakeClient((request) async {
        sentRequest = request;
        return _response('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
      });
      final client = OpenAiCompatibleChatClient(client: fake);
      final chunks = await client
          .streamCompletion(
            provider: _provider(
              endpoint: 'http://127.0.0.1:11434/v1',
              apiKey: null,
            ),
            history: const [],
            abortTrigger: Completer<void>().future,
          )
          .toList();

      expect(chunks, ['ok']);
      expect(sentRequest.url.toString(),
          'http://127.0.0.1:11434/v1/chat/completions');
      expect(sentRequest.headers.containsKey('authorization'), isFalse);
    });

    test('sends selected attachments as read-only user context', () async {
      late http.BaseRequest sentRequest;
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          sentRequest = request;
          return _response(
            'data: {"choices":[{"delta":{"content":"Reviewed"}}]}\n\n',
          );
        }),
      );

      await client
          .streamCompletion(
            provider: _provider(),
            history: const [
              ChatMessage(
                id: 'user-file-1',
                role: ChatMessageRole.user,
                content: 'Explain this file',
                status: ChatMessageStatus.complete,
                attachments: [
                  ChatAttachment(
                    relativePath: 'lib/example.dart',
                    content: 'const answer = 42;',
                    sizeBytes: 19,
                  ),
                ],
              ),
            ],
            abortTrigger: Completer<void>().future,
          )
          .toList();

      final body = jsonDecode((sentRequest as http.Request).body)
          as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
      expect(messages.single['role'], 'user');
      expect(messages.single['content'], contains('lib/example.dart'));
      expect(messages.single['content'], contains('const answer = 42;'));
      expect(messages.single['content'], contains('Explain this file'));
      expect(messages.single['content'], isNot(contains('C:\\Users\\')));
    });

    test('rejects non-HTTPS remote endpoints before making a request',
        () async {
      var requestSent = false;
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          requestSent = true;
          return _response('');
        }),
      );

      await expectLater(
        client
            .streamCompletion(
              provider: _provider(endpoint: 'http://api.example.test/v1'),
              history: const [],
              abortTrigger: Completer<void>().future,
            )
            .toList(),
        throwsA(isA<ChatConnectionException>()),
      );
      expect(requestSent, isFalse);
    });

    test(
        'turns provider status and malformed streaming events into safe errors',
        () async {
      final unauthorized = OpenAiCompatibleChatClient(
        client: _FakeClient((_) async => _response('secret body', status: 401)),
      );
      await expectLater(
        unauthorized
            .streamCompletion(
              provider: _provider(),
              history: const [],
              abortTrigger: Completer<void>().future,
            )
            .toList(),
        throwsA(
          isA<ChatConnectionException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 401'),
          ),
        ),
      );

      final malformed = OpenAiCompatibleChatClient(
        client: _FakeClient((_) async => _response('data: {bad json}\n\n')),
      );
      await expectLater(
        malformed
            .streamCompletion(
              provider: _provider(),
              history: const [],
              abortTrigger: Completer<void>().future,
            )
            .toList(),
        throwsA(isA<ChatConnectionException>()),
      );
    });

    test('forwards stop cancellation to the HTTP request', () async {
      final abort = Completer<void>();
      final observedAbort = Completer<void>();
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) {
          final abortable = request as http.AbortableRequest;
          return abortable.abortTrigger!.then((_) {
            observedAbort.complete();
            throw http.RequestAbortedException(request.url);
          });
        }),
      );
      final response = client
          .streamCompletion(
            provider: _provider(),
            history: const [],
            abortTrigger: abort.future,
          )
          .toList();
      abort.complete();

      await expectLater(response, throwsA(isA<ChatConnectionException>()));
      await observedAbort.future;
    });
  });
}

String _event(Map<String, Object?> json) => 'data: ${jsonEncode(json)}\n\n';

http.StreamedResponse _response(String body, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status);

ProviderProfile _provider({
  String endpoint = 'https://api.example.test/v1',
  String? apiKey = 'test-secret',
}) =>
    ProviderProfile(
      id: 'test-provider',
      name: 'Test Provider',
      model: 'test-model',
      endpoint: endpoint,
      onDevice: false,
      apiKey: apiKey,
    );

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
