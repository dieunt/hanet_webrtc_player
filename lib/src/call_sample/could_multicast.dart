// ignore_for_file: avoid_print, prefer_typing_uninitialized_variables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:core';
import 'dart:async';
import 'dart:typed_data';
import 'signaling.dart';
import 'event_bus_util.dart';
import 'event_message.dart';
import 'random_string.dart';
import '../utils/video_info.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../utils/LogUtil.dart';

typedef BuildWidget = Widget Function();

// ignore: must_be_immutable
class PartRefreshWidget extends StatefulWidget {
  PartRefreshWidget(Key key, this._child) : super(key: key);
  BuildWidget _child;
  @override
  State<StatefulWidget> createState() {
    return PartRefreshWidgetState(_child);
  }
}

class PartRefreshWidgetState extends State<PartRefreshWidget> {
  BuildWidget child;
  PartRefreshWidgetState(this.child);
  @override
  Widget build(BuildContext context) {
    return child.call();
  }

  void update() {
    setState(() {});
  }
}

class CouldMulticastPlayer extends StatefulWidget {
  static String tag = 'Could Player';
  final String peerId;
  final String selfId;
  final bool usedatachannel;

  CouldMulticastPlayer(
      {required this.selfId,
      required this.peerId,
      required this.usedatachannel});

  @override
  _CouldMulticastPlayerState createState() => _CouldMulticastPlayerState();
}

class _CouldMulticastPlayerState extends State<CouldMulticastPlayer> {
  String? _selfId;
  String? _peerId;
  String? _sid;
  bool _dataChannelOpened = false;
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _usedatachannel = false;
  String sessionIpeerid = "";
  String _current_serveraddr = "";
  String _temp_current_serveraddr = "";
  String _temp_current_filename = "";
  int _temp_current_event = 0;
  bool _inited = false;
  double _playindex = 0;
  bool _slider_change = false;
  bool _showremotevideo = true;
  bool _playing = false;

  List<VideoInfo> _videoList = [];
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();

  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc.qq-kan.com:3478'},
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
      {'googCpuOveruseDetection': false},
      {'googSuspendBelowMinBitrate': true},
    ]
  };

  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  var _recvMsgEvent;

  // ignore: unused_element
  _CouldMulticastPlayerState();
  GlobalKey<PartRefreshWidgetState> globalKey = new GlobalKey();

  @override
  initState() {
    super.initState();
    if (_inited == false) {
      _inited = true;
      _selfId = widget.selfId;
      _peerId = widget.peerId;
      _sid = randomNumeric(32);

      _usedatachannel = widget.usedatachannel;
      _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
        onMessage(event.msg);
      });
      initRenderers();
      _initWebrtc();
    }
  }

  /*
    注：初始化显示控件
  */
  initRenderers() async {
    await _remoteRenderer.initialize();
    _remoteRenderer.onFirstFrameRendered = () {
      setState(() {
        // _showremotevideo = true;
      });
    };
    _remoteRenderer.onResize = () {};
  }

  @override
  deactivate() {
    super.deactivate();
    Close();
    eventBus.off(_recvMsgEvent);
    _remoteRenderer.dispose();
  }

/*
  函数 ：初始化 websocket_send_getfilelists_msg();
  注 ：生成一个 Signaling 类，并实现相应回调函数

*/
  void _initWebrtc() {
    _websocket_send_create_multicast_msg();
  }

  void onMessage(message) async {
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    print('<<<<<<<<<<<<<<<<<<<<<<  :$message');
    switch (eventName) {
      case "_CreateMulticast":
        {
          var message = data["message"];
          if (message != null && message.toString().contains("sucessed")) {
            var address = data["address"];
            if (address != null) {
              _current_serveraddr = address.toString();
              if (_current_serveraddr.isNotEmpty) {
                _websocket_send_join_multicast_msg(_current_serveraddr);
              }
            }
          }
        }
        break;
      case "_JoinMulticast":
        {
          var message = data["message"];
          if (message != null && message.toString().contains("sucessed")) {
            var from = data["from"];
            if (from != null) {
              sessionIpeerid = from.toString();
            }
          }
        }
        break;
      case "_offer":
        {
          var iceServers = data['iceservers'];
          print(
              '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer iceServers  :$iceServers');
          if (iceServers != null && iceServers.toString().isNotEmpty) {
            _iceServers = _decoder.convert(iceServers);
            var sdp = data['sdp'];
            var peerconnect = await _createPeerConnection(
                audio: true, video: true, dataChannel: true);
            await peerconnect
                .setRemoteDescription(RTCSessionDescription(sdp, "offer"));
            await _createAnswer(peerconnect);
          } else {}
        }
        break;
      case "_answer":
        {}
        break;
      case "_ice_candidate":
        {}
        break;
      case "_session_disconnected":
        {
          Close();
        }
        break;
      case "_could_session_failed":
        {
          Close();
        }
        break;
      case "_ping":
        {}
        break;
      default:
        break;
    }
  }

  _websocket_send(eventName, data) {
    eventBus.emit(SendMsgEvent(eventName, data));
  }

  _websocket_send_create_multicast_msg() {
    _websocket_send('__CreateMulticast', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
    });
  }

  _websocket_send_join_multicast_msg(String serveraddress) {
    _websocket_send('__JoinMulticast', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'address': serveraddress,
    });
  }

  _websocket_send_exit_multicast_msg(String serveraddress) {
    _websocket_send('__ExitMulticast', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'address': serveraddress,
    });
  }

  _websocket_send_leave_multicast_msg(String serveraddress) {
    _websocket_send('__LeaveMulticast', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'address': serveraddress,
    });
  }

  _websocket_send_disconnected_msg() {
    _websocket_send('__disconnected', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': sessionIpeerid,
    });
  }

  // ignore: non_constant_identifier_names
  _send_datachennel_msg(event, data) {
    if (_dataChannelOpened) {
      var request = Map();
      request["eventName"] = event;
      request["data"] = data;
      var message = _encoder.convert(request);
      print('_send_datachennel_msg: $message');
      dc?.send(RTCDataChannelMessage(message));
    }
  }

  void onDataChannelTxtMessage(message) async {
    //print('ondatachennel Message recv $message');
  }

  Future<void> _createAnswer(RTCPeerConnection peerConnection) async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s =
          await peerConnection.createAnswer(dcConstraints);

      await peerConnection.setLocalDescription(s);

      LogUtil.d("_createAnswer ${s.sdp}");
      _websocket_send('__answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': _sid,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': sessionIpeerid
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(
      {required bool audio,
      required bool video,
      required bool dataChannel}) async {
    //print(_iceServers);
    RTCPeerConnection peerConnection = await createPeerConnection({
      ..._iceServers,
      ...{'continualGatheringPolicy': 'gather_continually'},
      ...{'tcpCandidatePolicy': 'disabled'},
      ...{'disableIpv6': true},
      ...{'sdpSemantics': sdpSemantics}
    }, _config);
    print('peerConnection iceServers $_iceServers');

    peerConnection.onIceCandidate = (candidate) async {
      var szcandidate = candidate.candidate;
      var sdpMLineIndex = candidate.sdpMLineIndex;
      var sdpMid = candidate.sdpMid;
      print(
          'send candidate  sdpMLineIndex: $sdpMLineIndex sdpMid: $sdpMid candidate: $szcandidate');

      // This delay is needed to allow enough time to try an ICE candidate
      // before skipping to the next one. 1 second is just an heuristic value
      // and should be thoroughly tested in your own environment.
      await Future.delayed(
          const Duration(milliseconds: 10),
          () => _websocket_send('__ice_candidate', {
                'sessionId': _sid,
                'sessionType': "flutter",
                'messageId': randomNumeric(32),
                'from': _selfId,
                'to': sessionIpeerid,
                "candidate": _encoder.convert({
                  'candidate': candidate.candidate,
                  'sdpMid': candidate.sdpMid,
                  'sdpMLineIndex': candidate.sdpMLineIndex
                })
              }));
    };

    peerConnection.onSignalingState = (state) {
      print('onSignalingState: $state');
    };
    peerConnection.onConnectionState = (state) {
      print('onConnectionState: $state');
    };
    peerConnection.onIceGatheringState = (state) {
      print('onIceGatheringState: $state');
    };
    peerConnection.onIceConnectionState = (state) {
      print('onIceConnectionState: $state');
    };
    peerConnection.onAddStream = (stream) {};
    peerConnection.onRemoveStream = (stream) {};
    peerConnection.onAddTrack = (stream, track) {
      if (track.kind == "video") {
        _remoteRenderer.srcObject = stream;
      }
    };
    peerConnection.onRemoveTrack = (stream, track) {
      if (track.kind == "video") {
        _remoteRenderer.srcObject = null;
      }
    };
    peerConnection.onDataChannel = (channel) {
      _addDataChannel(channel);
    };
    pc = peerConnection;
    return peerConnection;
  }

  Future<void> _closePeerConnection() async {
    await dc?.close();
    await pc?.close();
    await pc?.dispose();
  }

  void Close() async {
    print('Close');
    if (sessionIpeerid.isNotEmpty) {
      _websocket_send_disconnected_msg();
    }

    if (_current_serveraddr.isNotEmpty) {
      _websocket_send_leave_multicast_msg(_current_serveraddr);
    }

    await _closePeerConnection();
  }

  _addDataChannel(RTCDataChannel datachennel) {
    dc = datachennel;
    datachennel.onDataChannelState = (state) {
      var lable1 = datachennel.label;
      print('_addDataChannel :: $lable1 onDataChannelState: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannelOpened = true;
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _dataChannelOpened = false;
      }
    };
    datachennel.onMessage = (data) {
      if (data.isBinary) {
      } else {
        onDataChannelTxtMessage(data.text);
      }
    };
  }

/*
    函数 ： 挂起通话
    注： 发送一个__disconnect 消息 并返回上一页面
*/
  _hangUp() {
    Close();

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
          appBar: AppBar(
            title: Text('Could Multicast' +
                (_selfId != null ? ' [Your ID ($_selfId)] ' : '')),
          ),
          body: OrientationBuilder(builder: (context, orientation) {
            return Container(
              child: Stack(children: <Widget>[
                Positioned(
                  left: 0.0,
                  right: 0.0,
                  top: 0.0,
                  height: 200.0,
                  child: Stack(children: [
                    Container(
                      margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      child: RTCVideoView(_remoteRenderer),
                      decoration: BoxDecoration(color: Colors.black),
                    ),
                  ]),
                ),
              ]),
            );
          })),
      onWillPop: () {
        //监听到退出按键
        _hangUp();
        return Future<bool>.value(true);
      },
    );
  }
}
