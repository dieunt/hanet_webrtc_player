import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'websocket_base.dart';
import 'websocket_native.dart' if (dart.library.html) 'websocket_web.dart';
import 'utils.dart'; // Import LogUtil từ utils

class WebSocket {
  final String url;
  WebSocketBase? _webSocket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  WebSocket(this.url);

  Function()? onOpen;
  Function(dynamic msg)? onMessage;
  Function(int code, String reason)? onClose;

  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      _webSocket = PlatformWebSocket(url);
      _webSocket?.onOpen = () {
        _startHeartbeat();
        _reconnectAttempts = 0; // Reset attempts khi kết nối thành công
        onOpen?.call();
      };
      _webSocket?.onMessage = onMessage;
      _webSocket?.onClose = (code, reason) {
        _stopHeartbeat();
        onClose?.call(code, reason);
        _reconnect();
      };
      await _webSocket?.connect();
    } catch (e) {
      LogUtil.d('Failed to connect to WebSocket: $e');
      _reconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (isConnected) {
        send('ping');
        LogUtil.d('Heartbeat sent: ping');
      } else {
        _stopHeartbeat();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _reconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      LogUtil.d('Max reconnection attempts reached ($_maxReconnectAttempts)');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      LogUtil.d('Reconnecting... Attempt $_reconnectAttempts');
      connect();
    });
  }

  void send(dynamic data) {
    _webSocket?.send(data);
  }

  void close() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _webSocket?.close();
  }

  bool get isConnected => _webSocket?.isConnected ?? false;

  void listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) {
    _webSocket?.listen(
      onData,
      onError: onError,
      onDone: onDone,
    );
  }

  void dispose() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    close();
  }
}