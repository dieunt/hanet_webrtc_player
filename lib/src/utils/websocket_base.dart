import 'dart:async';

/// Abstract base class for WebSocket implementations
abstract class WebSocketBase {
  /// Callback when connection is established
  Function()? onOpen;

  /// Callback when a message is received
  Function(dynamic msg)? onMessage;

  /// Callback when connection is closed
  Function(int code, String reason)? onClose;

  /// Connect to the WebSocket server
  Future<void> connect();

  /// Send data through the WebSocket
  void send(dynamic data);

  /// Close the WebSocket connection
  void close();

  /// Get the current connection state
  bool get isConnected;

  /// Listen for data from the WebSocket
  void listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  });
}
