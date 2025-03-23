import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'websocket_base.dart';

/// Native WebSocket implementation for non-web platforms
class NativeWebSocket extends WebSocketBase {
  final String _url;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isConnecting = false;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  int _reconnectAttempts = 0;

  NativeWebSocket(this._url);

  @override
  bool get isConnected => _socket?.readyState == WebSocket.open;

  @override
  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      _socket = await _connectForSelfSignedCert(_url);
      _setupSocketListeners();
      _startHeartbeat();
      _reconnectAttempts = 0;
      onOpen?.call();
    } catch (e) {
      _handleError(e);
    } finally {
      _isConnecting = false;
    }
  }

  void _setupSocketListeners() {
    _socket?.listen(
      (data) => onMessage?.call(data),
      onDone: () {
        _handleClose();
      },
      onError: (error) {
        _handleError(error);
      },
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (isConnected) {
        send('ping');
      }
    });
  }

  void _handleClose() {
    _heartbeatTimer?.cancel();
    print('WebSocket closed by server');
    onClose?.call(
        _socket?.closeCode ?? 500, _socket?.closeReason ?? 'Unknown reason');
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
    _socket?.add(data);
  }

  @override
  void close() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.close();
  }

  Future<WebSocket> _connectForSelfSignedCert(String url) async {
    try {
      final key =
          base64.encode(List<int>.generate(8, (_) => Random().nextInt(255)));
      final client = HttpClient(context: SecurityContext());

      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        print('NativeWebSocket: Allow self-signed certificate => $host:$port');
        return true;
      };

      final request = await client.getUrl(Uri.parse(url));
      request.headers
        ..add('Connection', 'Upgrade')
        ..add('Upgrade', 'websocket')
        ..add('Sec-WebSocket-Version', '13')
        ..add('Sec-WebSocket-Key', key.toLowerCase());

      final response = await request.close();
      final socket = await response.detachSocket();

      return WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'signaling',
        serverSide: false,
      );
    } catch (e) {
      throw Exception('Failed to establish WebSocket connection: $e');
    }
  }
}
