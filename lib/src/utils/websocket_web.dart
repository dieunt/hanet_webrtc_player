import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'websocket_base.dart';
import 'utils.dart'; // Import LogUtil từ utils

class PlatformWebSocket implements WebSocketBase {
  final String _url;
  html.WebSocket? _webSocket;

  PlatformWebSocket(String url) : _url = url.replaceAll('https:', 'wss:');

  @override
  Function()? onOpen;

  @override
  Function(dynamic msg)? onMessage;

  @override
  Function(int code, String reason)? onClose;

  @override
  Future<void> connect() async {
    try {
      _webSocket = html.WebSocket(_url);
      _webSocket?.onOpen.listen((_) {
        onOpen?.call();
      });

      _webSocket?.onMessage.listen((event) {
        onMessage?.call(event.data);
      });

      _webSocket?.onClose.listen((event) {
        onClose?.call(event.code ?? 1000, event.reason ?? 'Connection closed');
      });

      _webSocket?.onError.listen((event) {
        onClose?.call(500, 'WebSocket error: $event');
      });
    } catch (e) {
      onClose?.call(500, e.toString());
    }
  }

  @override
  void send(dynamic data) {
    if (_webSocket != null && _webSocket?.readyState == html.WebSocket.OPEN) {
      _webSocket?.send(data);
    } else {
      LogUtil.d('WebSocket not connected, message $data not sent');
    }
  }

  @override
  void close() {
    _webSocket?.close();
  }

  @override
  bool get isConnected => _webSocket?.readyState == html.WebSocket.OPEN;

  @override
  void listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) {
    _webSocket?.onMessage.listen(
      (event) => onData(event.data),
      onError: onError,
      onDone: onDone,
    );
  }
}