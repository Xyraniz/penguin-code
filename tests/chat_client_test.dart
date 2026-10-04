import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:penguin_code/models.dart';
import 'package:penguin_code/services/openai_compatible_chat_client.dart';

void main() {
  group('OpenAiCompatibleChatClient', () {
    test('discovers models and parses optional capability metadata', () async {
      late http.BaseRequest sentRequest;
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          sentRequest = request;
          return _response(jsonEncode({
            'object': 'list',
            'data': [
              {
                'id': 'reasoner-v2',
                'display_name': 'Reasoner V2',
                'context_length': 65536,
                'max_output_tokens': 8192,
                'architecture': {
                  'input_modalities': ['text', 'image'],
                },
                'capabilities': {'tools': true, 'reasoning': true},
                'reasoningEfforts': {
                  'off': null,
                  'low': 'low',
                  'max': 'xhigh',
                },
              },
              {
                'id': 'text-only',
                'supports_images': false,
                'supported_reasoning_efforts': ['high'],
              },
              {'id': 'reasoner-v2'},
              {'id': ''},
            ],
          }));
        }),
      );

      final models = await client.discoverModels(
        provider:
            _provider(endpoint: 'https://api.example.test/v1/chat/completions'),
      );

      expect(sentRequest.method, 'GET');
      expect(sentRequest.url.toString(), 'https://api.example.test/v1/models');
      expect(sentRequest.headers['authorization'], 'Bearer test-secret');
      expect(models.map((model) => model.id), ['reasoner-v2', 'text-only']);
      expect(models.first.displayName, 'Reasoner V2');
      expect(models.first.contextWindow, 65536);
      expect(models.first.maxOutputTokens, 8192);
      expect(models.first.supportsImages, isTrue);
      expect(models.first.supportsTools, isTrue);
      expect(models.first.canReason, isTrue);
      expect(models.first.reasoningEfforts, {
        'off': null,
        'low': 'low',
        'max': 'xhigh',
      });
      expect(models.last.supportsImages, isFalse);
      expect(models.last.supportsTools, isNull);
      expect(models.last.reasoningEfforts, {'high': 'high'});
    });

    test('discovers models from a local provider without an API key', () async {
      late http.BaseRequest sentRequest;
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          sentRequest = request;
          return _response(jsonEncode([
            {'id': 'qwen3:8b'},
          ]));
        }),
      );

      final models = await client.discoverModels(
        provider: _provider(
          endpoint: 'http://127.0.0.1:11434/v1/',
          apiKey: null,
        ),
      );

      expect(sentRequest.url.toString(), 'http://127.0.0.1:11434/v1/models');
      expect(sentRequest.headers.containsKey('authorization'), isFalse);
      expect(models.single.id, 'qwen3:8b');
    });

    test('decodes unexpected tool calls even when tool definitions are omitted',
        () async {
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((_) async => _response([
              _event({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call-1',
                          'function': {
                            'name': 'read_project_file',
                            'arguments': '{"path":"README.md"}',
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
              'data: [DONE]\n\n',
            ].join())),
      );

      final events = await client
          .streamEvents(
            provider: _provider(),
            history: const [],
            abortTrigger: Completer<void>().future,
            enableProjectTools: false,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.single, isA<ChatToolCallEvent>());
      expect(
        (events.single as ChatToolCallEvent).toolCall.name,
        'read_project_file',
      );
    });

    test('reports sanitized model discovery errors', () async {
      final unauthorized = OpenAiCompatibleChatClient(
        client: _FakeClient((_) async => _response('secret body', status: 401)),
      );
      await expectLater(
        unauthorized.discoverModels(provider: _provider()),
        throwsA(
          isA<ChatConnectionException>()
              .having((error) => error.message, 'message', contains('HTTP 401'))
              .having((error) => error.message, 'message',
                  isNot(contains('secret'))),
        ),
      );

      final malformed = OpenAiCompatibleChatClient(
        client: _FakeClient((_) async => _response('{bad json}')),
      );
      await expectLater(
        malformed.discoverModels(provider: _provider()),
        throwsA(isA<ChatConnectionException>()),
      );
    });

    test('maps only declared reasoning efforts to the provider request',
        () async {
      final requests = <http.BaseRequest>[];
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          requests.add(request);
          return _response(
            'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
          );
        }),
      );
      final provider = _provider().copyWith(
        models: const [
          ModelProfile(
            id: 'test-model',
            reasoningEfforts: {'off': null, 'max': 'xhigh'},
          ),
        ],
      );

      await client
          .streamEvents(
            provider: provider,
            history: const [],
            abortTrigger: Completer<void>().future,
            reasoningEffort: 'max',
          )
          .toList();
      final maxBody = jsonDecode((requests.single as http.Request).body)
          as Map<String, dynamic>;
      expect(maxBody['reasoning_effort'], 'xhigh');

      await client
          .streamEvents(
            provider: provider,
            history: const [],
            abortTrigger: Completer<void>().future,
            reasoningEffort: 'off',
          )
          .toList();
      final offBody = jsonDecode((requests.last as http.Request).body)
          as Map<String, dynamic>;
      expect(offBody.containsKey('reasoning_effort'), isFalse);

      await expectLater(
        client
            .streamEvents(
              provider: provider,
              history: const [],
              abortTrigger: Completer<void>().future,
              reasoningEffort: 'high',
            )
            .toList(),
        throwsA(isA<ChatConnectionException>()),
      );
      expect(requests, hasLength(2));
    });

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

    test('keeps request context within the limit using recent user turns',
        () async {
      late http.BaseRequest sentRequest;
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          sentRequest = request;
          return _response(
              'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
        }),
      );

      await client
          .streamCompletion(
            provider: _provider(),
            history: [
              ChatMessage(
                id: 'old-user',
                role: ChatMessageRole.user,
                content: 'x' * OpenAiCompatibleChatClient.maxRequestBodyBytes,
                status: ChatMessageStatus.complete,
              ),
              const ChatMessage(
                id: 'old-assistant',
                role: ChatMessageRole.assistant,
                content: 'Older answer',
                status: ChatMessageStatus.complete,
              ),
              const ChatMessage(
                id: 'latest-user',
                role: ChatMessageRole.user,
                content: 'Current question',
                status: ChatMessageStatus.complete,
              ),
              const ChatMessage(
                id: 'streaming-placeholder',
                role: ChatMessageRole.assistant,
                content: '',
                status: ChatMessageStatus.streaming,
              ),
            ],
            abortTrigger: Completer<void>().future,
          )
          .toList();

      final body = jsonDecode((sentRequest as http.Request).body)
          as Map<String, dynamic>;
      expect(body['messages'], [
        {'role': 'user', 'content': 'Current question'},
      ]);
      expect(utf8.encode((sentRequest as http.Request).body).length,
          lessThanOrEqualTo(OpenAiCompatibleChatClient.maxRequestBodyBytes));
    });

    test('rejects a single message larger than the request limit', () async {
      var requestSent = false;
      final client = OpenAiCompatibleChatClient(
        client: _FakeClient((request) async {
          requestSent = true;
          return _response(
              'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
        }),
      );

      await expectLater(
        client
            .streamCompletion(
              provider: _provider(),
              history: [
                ChatMessage(
                  id: 'oversized-user',
                  role: ChatMessageRole.user,
                  content: 'x' *
                      (OpenAiCompatibleChatClient.maxRequestBodyBytes + 1),
                  status: ChatMessageStatus.complete,
                ),
              ],
              abortTrigger: Completer<void>().future,
            )
            .toList(),
        throwsA(
          isA<ChatConnectionException>().having(
            (error) => error.message,
            'message',
            contains('384 KiB request limit'),
          ),
        ),
      );
      expect(requestSent, isFalse);
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
