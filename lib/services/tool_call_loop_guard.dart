import 'dart:convert';

import '../models.dart';

/// Stops an agent response from executing the same tool call indefinitely.
///
/// The first four identical attempts are allowed. A fifth consecutive attempt
/// is blocked before execution. Create one guard per user response so a new
/// request starts with a fresh limit.
class ToolCallLoopGuard {
  static const maxAllowedIdenticalAttempts = 4;

  String? _lastFingerprint;
  int _consecutiveAttempts = 0;

  ToolCallLoopDecision inspect(AgentToolCall call) {
    final fingerprint = _fingerprint(call);
    if (fingerprint == _lastFingerprint) {
      _consecutiveAttempts++;
    } else {
      _lastFingerprint = fingerprint;
      _consecutiveAttempts = 1;
    }

    return ToolCallLoopDecision(
      consecutiveAttempts: _consecutiveAttempts,
      blocked: _consecutiveAttempts > maxAllowedIdenticalAttempts,
    );
  }

  String _fingerprint(AgentToolCall call) {
    final arguments = call.hasValidArguments
        ? call.arguments
        : _decodeArgumentsOrRaw(call.rawArguments);
    return jsonEncode([call.name, _canonicalizeJson(arguments)]);
  }

  Object? _decodeArgumentsOrRaw(String rawArguments) {
    try {
      return jsonDecode(rawArguments);
    } on FormatException {
      return rawArguments;
    }
  }

  Object? _canonicalizeJson(Object? value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalizeJson(value[key]),
      };
    }
    if (value is List<dynamic>) {
      return value.map(_canonicalizeJson).toList(growable: false);
    }
    return value;
  }
}

class ToolCallLoopDecision {
  const ToolCallLoopDecision({
    required this.consecutiveAttempts,
    required this.blocked,
  });

  final int consecutiveAttempts;
  final bool blocked;
}
