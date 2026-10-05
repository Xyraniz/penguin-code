import '../models.dart';

class ChatHistoryMatch {
  const ChatHistoryMatch({
    required this.conversation,
    required this.message,
    required this.excerpt,
    required this.score,
  });

  final ChatConversation conversation;
  final ChatMessage? message;
  final String excerpt;
  final int score;
}

abstract final class ChatHistorySearch {
  static const maxQueryCharacters = 300;
  static const maxResults = 20;
  static const maxExcerptCharacters = 320;

  static final _tokenPattern = RegExp(r'[a-zA-Z0-9À-ÖØ-öø-ÿĀ-ž]{2,}');
  static const _stopWords = {
    'about',
    'after',
    'are',
    'and',
    'any',
    'as',
    'at',
    'be',
    'been',
    'by',
    'but',
    'can',
    'could',
    'did',
    'does',
    'do',
    'for',
    'from',
    'had',
    'have',
    'her',
    'his',
    'help',
    'how',
    'in',
    'is',
    'it',
    'into',
    'just',
    'last',
    'me',
    'no',
    'not',
    'of',
    'off',
    'or',
    'our',
    'she',
    'the',
    'their',
    'them',
    'there',
    'these',
    'they',
    'this',
    'those',
    'was',
    'were',
    'we',
    'que',
    'what',
    'when',
    'where',
    'which',
    'who',
    'why',
    'with',
    'so',
    'to',
    'you',
    'your',
    'would',
    'yo',
    'tú',
    'tu',
    'de',
    'del',
    'como',
    'con',
    'cuando',
    'desde',
    'donde',
    'el',
    'ella',
    'en',
    'era',
    'es',
    'esta',
    'está',
    'esto',
    'fue',
    'había',
    'has',
    'he',
    'la',
    'las',
    'lo',
    'los',
    'mi',
    'mis',
    'para',
    'por',
    'pero',
    'porque',
    'qué',
    'quién',
    'se',
    'sobre',
    'son',
    'un',
    'una',
    'uno',
    'y',
  };

  static List<ChatHistoryMatch> search({
    required List<ChatConversation> conversations,
    required Map<String, List<ChatMessage>> messagesByChatId,
    required String query,
    Set<String> excludedMessageIds = const {},
    int limit = 10,
    bool includeTitleMatches = true,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || query.length > maxQueryCharacters) {
      return const [];
    }
    final terms = _terms(normalizedQuery);
    if (terms.isEmpty) return const [];

    final matches = <({ChatHistoryMatch match, int order})>[];
    var order = 0;
    for (final conversation in conversations) {
      final title = conversation.title.toLowerCase();
      final titleMatches = terms.where(title.contains).length;
      var hasMessageMatch = false;
      final messages = messagesByChatId[conversation.id] ?? const [];
      for (final message in messages.reversed) {
        if (excludedMessageIds.contains(message.id) ||
            (message.role != ChatMessageRole.user &&
                message.role != ChatMessageRole.assistant) ||
            (message.status != ChatMessageStatus.complete &&
                message.status != ChatMessageStatus.stopped) ||
            message.toolCalls.isNotEmpty ||
            message.content.trim().isEmpty ||
            _containsCredentialLikeValue(message.content)) {
          continue;
        }
        final content = message.content.toLowerCase();
        final matchedTerms = terms.where(content.contains).toList();
        final phraseMatch = content.contains(normalizedQuery);
        final requiredMatches = (terms.length + 1) ~/ 2;
        if (matchedTerms.length < requiredMatches && !phraseMatch) continue;
        hasMessageMatch = true;
        final score = matchedTerms.length * 100 +
            (phraseMatch ? 80 : 0) +
            titleMatches * 10;
        matches.add((
          match: ChatHistoryMatch(
            conversation: conversation,
            message: message,
            excerpt: _excerpt(message.content, matchedTerms),
            score: score,
          ),
          order: order++,
        ));
      }
      if (includeTitleMatches && titleMatches > 0 && !hasMessageMatch) {
        matches.add((
          match: ChatHistoryMatch(
            conversation: conversation,
            message: null,
            excerpt: 'Conversation title match',
            score: titleMatches * 100,
          ),
          order: order++,
        ));
      }
    }

    matches.sort((left, right) {
      final scoreOrder = right.match.score.compareTo(left.match.score);
      if (scoreOrder != 0) return scoreOrder;
      final dateOrder = (right.match.conversation.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(left.match.conversation.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0));
      if (dateOrder != 0) return dateOrder;
      return left.order.compareTo(right.order);
    });
    return matches
        .take(limit.clamp(1, maxResults).toInt())
        .map((entry) => entry.match)
        .toList(growable: false);
  }

  static List<String> _terms(String value) => _tokenPattern
      .allMatches(value)
      .map((match) => match.group(0)!)
      .where((term) => term.length >= 2 && !_stopWords.contains(term))
      .toSet()
      .toList(growable: false);

  static String _excerpt(String content, List<String> matchedTerms) {
    final lowerContent = content.toLowerCase();
    var matchIndex = -1;
    for (final term in matchedTerms) {
      final index = lowerContent.indexOf(term);
      if (index >= 0 && (matchIndex < 0 || index < matchIndex)) {
        matchIndex = index;
      }
    }
    if (content.length <= maxExcerptCharacters) return content.trim();
    if (matchIndex < 0) return '${content.substring(0, maxExcerptCharacters)}…';

    var start =
        (matchIndex - maxExcerptCharacters ~/ 3).clamp(0, content.length);
    var end = (start + maxExcerptCharacters).clamp(0, content.length);
    if (start > 0 && _isLowSurrogate(content.codeUnitAt(start))) start--;
    if (end < content.length &&
        end > 0 &&
        _isHighSurrogate(content.codeUnitAt(end - 1))) {
      end--;
    }
    return '${start > 0 ? '…' : ''}${content.substring(start, end)}${end < content.length ? '…' : ''}';
  }

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  static bool _containsCredentialLikeValue(String value) => RegExp(
        r'(?:bearer\s+[A-Za-z0-9._~+/-]{12,}|sk-[A-Za-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:api[_ -]?key|password|passwd|secret|token)\s*[:=]\s*\S+)',
        caseSensitive: false,
      ).hasMatch(value);
}
