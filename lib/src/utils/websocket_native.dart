import 'dart:async';
import 'dart:io' as io;
import 'dart:math';
import 'dart:convert';
import 'websocket_base.dart';
import 'LogUtil.dart'; // Import LogUtil từ utils

class PlatformWebSocket implements WebSocketBase {
  final String url;
  io.WebSocket? _webSocket;

  PlatformWebSocket(this.url);

  @override
  Function()? onOpen;

  @override
  Function(dynamic msg)? onMessage;

  @override
  Function(int code, String reason)? onClose;

  @override
  Future<void> connect() async {
    try {
      _webSocket = await _connectForSelfSignedCert(url);
      onOpen?.call();
      _webSocket?.listen(
        (data) {
          onMessage?.call(data);
        },
        onDone: () {
          LogUtil.d('Closed by server');
          onClose?.call(
              _webSocket?.closeCode ?? 1000, _webSocket?.closeReason ?? "null");
        },
        onError: (error) {
          onClose?.call(500, 'WebSocket error: $error');
        },
      );
    } catch (e) {
      onClose?.call(500, e.toString());
    }
  }

  Future<io.WebSocket> _connectForSelfSignedCert(String url) async {
    try {
      Random r = Random();
      String key = base64.encode(List<int>.generate(8, (_) => r.nextInt(255)));
      io.HttpClient client = io.HttpClient(context: io.SecurityContext());
      client.badCertificateCallback =
          (io.X509Certificate cert, String host, int port) {
        LogUtil.d('Allow self-signed certificate => $host:$port');
        return true;
      };

      io.HttpClientRequest request = await client.getUrl(Uri.parse(url));
      request.headers.add('Connection', 'Upgrade');
      request.headers.add('Upgrade', 'websocket');
      request.headers.add('Sec-WebSocket-Version', '13');
      request.headers.add('Sec-WebSocket-Key', key.toLowerCase());

      io.HttpClientResponse response = await request.close();
      io.Socket socket = await response.detachSocket();
      var webSocket = io.WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'signaling',
        serverSide: false,
      );

      return webSocket;
    } catch (e) {
      throw e;
    }
  }

  @override
  void send(dynamic data) {
    if (_webSocket != null && isConnected) {
      _webSocket?.add(data);
    } else {
      LogUtil.d('WebSocket not connected, message $data not sent');
    }
  }

  @override
  void close() {
    _webSocket?.close();
  }

  @override
  bool get isConnected => _webSocket?.readyState == io.WebSocket.open;

  @override
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
}