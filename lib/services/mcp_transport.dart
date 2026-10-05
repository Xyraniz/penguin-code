import '../models.dart';

const mcpMaxMessageBytes = 1024 * 1024;

class McpException implements Exception {
  const McpException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class McpTransport {
  Stream<String> get lines;

  void sendLine(String line);

  Future<void> close();
}

typedef McpStdioTransport = McpTransport;

typedef McpTransportFactory = Future<McpTransport> Function(
  McpServerProfile server,
);
