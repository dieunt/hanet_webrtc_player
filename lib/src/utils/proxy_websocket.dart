import 'websocket_base.dart';
import 'websocket.dart' if (dart.library.js) 'websocket_web.dart';

/// A proxy class that provides a platform-agnostic WebSocket interface
class ProxyWebSocket {
  final String _url;
  WebSocketBase? _socket;

  ProxyWebSocket(this._url);

  /// Callback when connection is established
  Function()? onOpen;

  /// Callback when a message is received
  Function(dynamic msg)? onMessage;

  /// Callback when connection is closed
  Function(int code, String reason)? onClose;

  /// Connect to the WebSocket server
  Future<void> connect() async {
    try {
      _socket = createWebSocket(_url);
      _socket?.onOpen = () => onOpen?.call();
      _socket?.onMessage = (msg) => onMessage?.call(msg);
      _socket?.onClose = (code, reason) => onClose?.call(code, reason);
      await _socket?.connect();
    } catch (e) {
      onClose?.call(500, e.toString());
    }
  }

  /// Send data through the WebSocket
  void send(dynamic data) {
    _socket?.send(data);
  }

  /// Close the WebSocket connection
  void close() {
    _socket?.close();
  }

  /// Get the current connection state
  bool get isConnected => _socket?.isConnected ?? false;
}

/// Factory function to create the appropriate WebSocket implementation
WebSocketBase createWebSocket(String url) {
  // The conditional import will handle the platform-specific implementation
  return NativeWebSocket(url);
}
