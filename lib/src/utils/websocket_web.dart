// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:async';
import 'websocket_base.dart';

/// WebSocket implementation for web platforms
class WebWebSocket extends WebSocketBase {
  String _url;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isConnecting = false;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  int _reconnectAttempts = 0;

  WebWebSocket(this._url) {
    _url = _url.replaceAll('https:', 'wss:');
  }

  @override
  bool get isConnected => _socket?.readyState == WebSocket.OPEN;

  @override
  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      _socket = WebSocket(_url);
      _setupSocketListeners();
      _startHeartbeat();
      _reconnectAttempts = 0;
    } catch (e) {
      _handleError(e);
    } finally {
      _isConnecting = false;
    }
  }

  void _setupSocketListeners() {
    _socket?.onOpen.listen((_) {
      onOpen?.call();
    });

    _socket?.onMessage.listen((e) {
      onMessage?.call(e.data);
    });

    _socket?.onClose.listen((e) {
      _handleClose(e.code ?? 500, e.reason);
    });

    _socket?.onError.listen((e) {
      _handleError(e);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (isConnected) {
        send('ping');
      }
    });
  }

  void _handleClose(int code, String? reason) {
    _heartbeatTimer?.cancel();
    print('WebSocket closed by server');
    onClose?.call(code, reason ?? 'Unknown reason');
    _attemptReconnect();
  }

  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    onClose?.call(500, error.toString());
    _attemptReconnect();
  }

  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      connect();
    });
  }

  @override
  void send(dynamic data) {
    if (!isConnected) {
      print('WebSocket not connected, message not sent');
      return;
    }
    _socket?.send(data);
  }

  @override
  void close() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.close();
  }
}
