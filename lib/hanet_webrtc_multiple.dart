import 'dart:core';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'src/call_sample/event_bus_util.dart';
import 'src/call_sample/event_message.dart';
import 'src/call_sample/random_string.dart';
import 'src/utils/LogUtil.dart';
import 'src/utils/ProxyWebsocket.dart';

typedef BuildWidget = Widget Function();

final String WSS_SERVER_URL = "https://webrtc-stream.hanet.ai/wswebclient/";

class HanetWebRTCMultipleSession {
  HanetWebRTCMultipleSession({required this.sid, required this.pid, required this.remoteRenderer, required this.mediarecoder});

  String pid;
  String sid;
  String videofilepath = "";

  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  RTCVideoRenderer remoteRenderer;
  MediaRecorder mediarecoder;
  MediaStream? _localStream;
  MediaStreamTrack? _remotevideotrack;
  MediaStreamTrack? _remoteaudiotrack;

  bool audio = false;
  bool video = false;
  bool dataChannel = false;
  bool _domainname = false;

  List<RTCIceCandidate> remoteCandidates = [];

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc-stream.hanet.ai:3478'},
    ]
  };

  Map<String, dynamic> _domainnameiceServers = {
    'iceServers': [
      {'url': 'stun:webrtc-stream.hanet.ai:3478'},
    ]
  };
}

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

class HanetWebRTCMultiple extends StatefulWidget {
  final List<String> peerIds;
  final VoidCallback? onOffline;
  final int showVideoWindow;
  final int showRowVideoWindow;

  const HanetWebRTCMultiple({
    Key? key,
    required this.peerIds,
    this.onOffline,
    this.showVideoWindow = 8,
    this.showRowVideoWindow = 2,
  }) : super(key: key);

  @override
  _HanetWebRTCMultipleState createState() => _HanetWebRTCMultipleState();
}

class _HanetWebRTCMultipleState extends State<HanetWebRTCMultiple> {
  // WebRTC variable
  String? _selfId;

  // widget util variable
  var _sendMsgEvent;
  var _recvMsgEvent;
  var _delSessionMsgEvent;
  var _newSessionMsgEvent;

  // WebSocket variable
  String _serverUrl = "";
  ProxyWebsocket? _socket;
  final _encoder = JsonEncoder();
  final _decoder = JsonDecoder();

  // WebRTC variable
  bool _inited = false;
  final List<HanetWebRTCMultipleSession> _sessions = [];
  final List<HanetWebRTCMultipleSession> _showsessions = [];

  String get sdpSemantics => WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
      {'googCpuOveruseDetection': false},
      {'googSuspendBelowMinBitrate': true},
    ],
  };

  @override
  initState() {
    super.initState();
    LogUtil.init(isDebug: true);

    _selfId = randomNumeric(32);
    _serverUrl = WSS_SERVER_URL + _selfId!;

    if (_inited == false) {
      _inited = true;
      _initEventBus();
      _webSocketConnect();
    }
  }

  @override
  deactivate() {
    super.deactivate();
    close();

    eventBus.off(_recvMsgEvent);
    eventBus.off(_sendMsgEvent);
    eventBus.off(_delSessionMsgEvent);
    eventBus.off(_newSessionMsgEvent);
    for (var i = 0; i < _sessions.length; i++) {
      HanetWebRTCMultipleSession sess = _sessions[i];
      _unInitRenderers(sess.remoteRenderer);
    }
  }

  /// ******************************************************
  /// WebSocket Connection Handler Start
  Future<void> _webSocketConnect() async {
    LogUtil.d('websocketconnect:: _serverUrl: $_serverUrl');
    _socket = ProxyWebsocket(_serverUrl);
    // onOpen
    _socket?.onOpen = () {
      LogUtil.d('websocketconnect::onOpen');
      _initWebrtc();
    };

    // onClose
    _socket?.onClose = (int code, String reason) {
      LogUtil.d('websocketconnect::onClose');
      Timer(const Duration(seconds: 5), () {
        _webSocketConnect();
      });
    };

    // onMessage
    _socket?.onMessage = (message) {
      eventBus.emit(ReciveMsgEvent(message));
    };

    await _socket?.connect();
  }

  _webSocketSend(eventName, data) {
    eventBus.emit(SendMsgEvent(eventName, data));
  }

  /// WebSocket Connection Handler End
  /// ******************************************************

  /// ******************************************************
  /// WebRTC Message Handler Start
  void _initWebrtc() {
    _sessions.clear();

    // Create sessions for all peerIds
    for (String peerId in widget.peerIds) {
      _createSession(
          sessionId: randomNumeric(32),
          peerId: peerId,
          remoteRenderer: RTCVideoRenderer(),
          mediarecoder: MediaRecorder(),
          focus: true);
    }

    for (var i = 0; i < _sessions.length; i++) {
      HanetWebRTCMultipleSession sess = _sessions[i];
      _initRenderers(sess.remoteRenderer);
    }

    for (var i = 0; i < _sessions.length; i++) {
      HanetWebRTCMultipleSession sess = _sessions[i];
      if (sess.pid.length > 0) {
        connect(sess);
      }
    }
  }

  _initRenderers(RTCVideoRenderer remoteRenderer) async {
    await remoteRenderer.initialize();
    remoteRenderer.onFirstFrameRendered = () {
      setState(() {});
    };
    remoteRenderer.onResize = () {};
  }

  _unInitRenderers(RTCVideoRenderer remoteRenderer) async {
    remoteRenderer.dispose();
  }

  Future<void> connect(HanetWebRTCMultipleSession sess) async {
    _webSocketSend('__connectto', {
      'sessionId': sess.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': sess.pid,
    });
  }

  void onMessage(message) async {
    // LogUtil.d('onMessage recv $message');
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    var sessionId = data['sessionId'];
    var peerId = data['from'];

    switch (eventName) {
      case '_create':
        {
          for (var i = 0; i < _sessions.length; i++) {
            HanetWebRTCMultipleSession sess = _sessions[i];
            if (sess.sid == sessionId) {
              var iceServers = data['iceServers'];
              if (iceServers != null) {
                sess._iceServers = _decoder.convert(iceServers);
              }

              var domainnameiceServers = data['domainnameiceServers'];
              if (domainnameiceServers != null) {
                sess._domainnameiceServers = _decoder.convert(domainnameiceServers);
                sess._domainname = true;
              }

              var state = data['state'];
              if (state != null) {
                if (compare(state, "online") == 0) {
                  startCall(sess);
                } else if (compare(state, "sleep") == 0) {
                  startCall(sess);
                } else {
                  print('onMessage :$peerId is $state');
                }
              } else {}
            }
          }
        }
        break;
      case '_call':
        {}
        break;
      case '_offer':
        {
          for (var i = 0; i < _sessions.length; i++) {
            HanetWebRTCMultipleSession sess = _sessions[i];
            if (sess.sid == sessionId) {
              var sdp = data['sdp'];
              LogUtil.v("_offer $sdp");
              await _createPeerConnectionByOffer(sess, true, true, true, sdp);
            }
          }
        }
        break;
      case '_answer':
        {}
        break;
      case '_ice_candidate':
        {
          for (var i = 0; i < _sessions.length; i++) {
            HanetWebRTCMultipleSession sess = _sessions[i];
            if (sess.sid == sessionId) {
              var candidateMap = data['candidate'];
              var candidateobject = _decoder.convert(candidateMap);
              var scandidate = candidateobject['candidate'];
              var nsdpMLineIndex = candidateobject['sdpMLineIndex'];
              var ssdpMid = candidateobject['sdpMid'];
              RTCIceCandidate candidate = RTCIceCandidate(scandidate, ssdpMid, nsdpMLineIndex);
              if (sess.pc != null) {
                print('addCandidate------------------- :$scandidate');
                await sess.pc?.addCandidate(candidate);
              } else {
                sess.remoteCandidates.add(candidate);
              }
            }
          }
        }
        break;
      case '_disconnected':
        {
          for (var i = 0; i < _sessions.length; i++) {
            HanetWebRTCMultipleSession sess = _sessions[i];
            if (sess.sid == sessionId) {
              closeSession(sess);
            }
          }
        }
        break;
      case '_session_failed':
        {
          for (var i = 0; i < _sessions.length; i++) {
            HanetWebRTCMultipleSession sess = _sessions[i];
            if (sess.sid == sessionId) {
              closeSession(sess);
            }
          }
        }
        break;
      case '_post_message':
        break;
      case '_connectinfo':
        LogUtil.d('onMessage recv $message');
        break;
      case '_ping':
        {}
        break;
      default:
        break;
    }
  }

  void startCall(HanetWebRTCMultipleSession sess) {
    _webSocketSend('__call', {
      "sessionId": sess.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': sess.pid,
      "mode": "live",
      "source": "SubStream",
      "datachannel": 'false',
      "audio": 'recvonly',
      "video": 'recvonly',
      "user": "admin",
      "pwd": "123456",
      "iceservers": _encoder.convert(sess._iceServers)
    });
  }

  Future<RTCPeerConnection> _createPeerConnectionByOffer(
      HanetWebRTCMultipleSession session, bool audio, bool video, bool dataChannel, String sdp) async {
    Map<String, dynamic> iceServers;
    if (session._domainname) {
      iceServers = _decoder.convert(_encoder.convert(session._domainnameiceServers));
    } else {
      iceServers = _decoder.convert(_encoder.convert(session._iceServers));
    }

    RTCPeerConnection peerConnection = await createPeerConnection({
      ...iceServers,
      ...{'continualGatheringPolicy': 'gather_continually'},
      ...{'tcpCandidatePolicy': 'disabled'},
      ...{'disableIpv6': true},
      ...{'sdpSemantics': sdpSemantics}
    }, _config);

    print('peerConnection iceServers------------------------------------------- $iceServers');
    session.pc = peerConnection;

    // if (session.audio || session.video) {
    //   MediaStream localstream = await createLocalStream(true, false, true);
    //   if (localstream != null) {
    //     session._localStream = localstream;

    //     switch (sdpSemantics) {
    //       case 'plan-b':
    //         if (localstream != null) {
    //           await peerConnection.addStream(localstream);
    //         }

    //         break;
    //       case 'unified-plan':
    //         // Unified-Plan
    //         if (localstream != null) {
    //           localstream.getTracks().forEach((track) {
    //             track.enabled = session._mute;
    //             peerConnection.addTrack(track, localstream);
    //           });
    //         }
    //         break;
    //     }
    //   }
    // }

    peerConnection.onIceCandidate = (candidate) async {
      var szcandidate = candidate.candidate;
      var sdpMLineIndex = candidate.sdpMLineIndex;
      var sdpMid = candidate.sdpMid;
      print('send candidate  sdpMLineIndex: $sdpMLineIndex sdpMid: $sdpMid candidate: $szcandidate');

      // This delay is needed to allow enough time to try an ICE candidate
      // before skipping to the next one. 1 second is just an heuristic value
      // and should be thoroughly tested in your own environment.
      await Future.delayed(
          const Duration(milliseconds: 10),
          () => _webSocketSend('__ice_candidate', {
                'sessionId': session.sid,
                'sessionType': "flutter",
                'messageId': randomNumeric(32),
                'from': _selfId,
                'to': session.pid,
                "candidate": _encoder.convert(
                    {'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex})
              }));
    };

    peerConnection.onSignalingState = (state) {
      print('onSignalingState: $state');
    };

    peerConnection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {}
      print('onConnectionState: $state');
    };

    peerConnection.onIceGatheringState = (state) {
      print('onIceGatheringState: $state');
    };

    peerConnection.onIceConnectionState = (state) {
      print('onIceConnectionState: $state');
    };

    peerConnection.onAddStream = (stream) {
      stream.getVideoTracks().forEach((videoTrack) {
        session._remotevideotrack = videoTrack;
        session.remoteRenderer.srcObject = stream;
      });
      stream.getAudioTracks().forEach((audioTrack) {
        audioTrack.enabled = false;
        session._remoteaudiotrack = audioTrack;
      });
    };

    peerConnection.onRemoveStream = (stream) {
      stream.getVideoTracks().forEach((videoTrack) {
        if (session._remotevideotrack == videoTrack) {
          session._remotevideotrack = null;
          session.remoteRenderer.srcObject = null;
        }
      });
      stream.getAudioTracks().forEach((audioTrack) {
        if (session._remoteaudiotrack == audioTrack) {
          session._remoteaudiotrack = null;
        }
      });
    };

    peerConnection.onAddTrack = (stream, track) {
      print('onAddTrack: stream' + stream.toString());
      print('onAddTrack track &&&&&&&&&&&&&&&&  ${track}  peerConnection id = ' + peerConnection.getPeerConnectionId());
      if (track.kind == "video") {
        session._remotevideotrack = track;
        session.remoteRenderer.srcObject = stream;
      } else if (track.kind == "audio") {
        track.enabled = false;
        session._remoteaudiotrack = track;
      }
    };

    peerConnection.onRemoveTrack = (stream, track) {
      if (track.kind == "video") {
        session.remoteRenderer.srcObject = null;
        session._remotevideotrack = null;
      }

      if (track.kind == "audio") {
        session._remoteaudiotrack = null;
      }
    };

    // peerConnection.onDataChannel = (channel) {
    //   channel.onDataChannelState = (state) {
    //     var lable1 = channel.label;
    //     if (state == RTCDataChannelState.RTCDataChannelOpen) {
    //       session._dataChannelOpened = true;
    //       session.dc = channel;
    //     } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
    //       session._dataChannelOpened = false;
    //     }

    //     print('_addDataChannel :: $lable1 onDataChannelState: $state');
    //   };
    //   channel.onMessage = (data) {
    //     if (data.isBinary) {
    //     } else {
    //       onDataChannelTxtMessage(session, data.text);
    //     }
    //   };
    // };

    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, "offer"));
    await _createAnswer(session, peerConnection);
    await _createDataChannel(session);

    if (session.remoteCandidates.isNotEmpty) {
      session.remoteCandidates.forEach((candidate) async {
        ;
        await peerConnection.addCandidate(candidate);
      });
      session.remoteCandidates.clear();
    }

    return peerConnection;
  }

  Future<HanetWebRTCMultipleSession> _createSession(
      {required String sessionId,
      required String peerId,
      required RTCVideoRenderer remoteRenderer,
      required MediaRecorder mediarecoder,
      required bool focus}) async {
    var newSession =
        HanetWebRTCMultipleSession(sid: sessionId, pid: peerId, remoteRenderer: remoteRenderer, mediarecoder: mediarecoder);

    _sessions.add(newSession);
    if (_showsessions.length < widget.showVideoWindow) {
      _showsessions.add(newSession);
    }

    return newSession;
  }

  Future<MediaStream> createLocalStream(bool audio, bool video, bool datachennel) async {
    print('createLocalStream: audio = $audio  video= $video datachennel = $datachennel');
    Map<String, dynamic> mediaConstraints = {};
    if (audio == false && video == false && datachennel == true) {
      mediaConstraints = {'audio': false, 'video': false};
    } else if (audio == true && video == true && (audio == true || video == true) && datachennel == true) {
      mediaConstraints = {
        'audio': audio,
        'video': video
            ? {
                'mandatory': {
                  'minWidth': '1280', // Provide your own width, height and frame rate here
                  'minHeight': '720',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false
      };
    } else if (audio == true && video == true && (audio == true || video == true) && datachennel == false) {
      mediaConstraints = {'audio': audio, 'video': video};
    } else if (audio == true && video == false && (audio == true || video == true) && datachennel == true) {
      mediaConstraints = {
        'audio': audio,
        'video': video
            ? {
                'mandatory': {
                  'minWidth': '1280', // Provide your own width, height and frame rate here
                  'minHeight': '720',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false
      };
    } else {
      mediaConstraints = {'audio': audio, 'video': video};
    }
    MediaStream stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return stream;
  }

  Future<void> _createAnswer(HanetWebRTCMultipleSession session, RTCPeerConnection pc) async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s = await pc.createAnswer(dcConstraints);
      await pc.setLocalDescription(s);

      _webSocketSend('__answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': session.sid,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': session.pid
      });
    } catch (e) {
      print(e.toString());
    }
  }

  // void _addDataChannel(RTCDataChannel channel) {
  //   channel.onDataChannelState = (e) {
  //     if (e == RTCDataChannelState.RTCDataChannelOpen) {
  //       LogUtil.d("datachennel :open");
  //       LogUtil.d(channel.label);
  //       LogUtil.d(channel.id);
  //       _dataChannelOpened = true;
  //       dc = channel;
  //       // _send_datachennel_msg_ex();
  //     } else if (e == RTCDataChannelState.RTCDataChannelClosing) {
  //     } else if (e == RTCDataChannelState.RTCDataChannelClosed) {
  //     } else if (e == RTCDataChannelState.RTCDataChannelConnecting) {}
  //   };

  //   channel.onMessage = (RTCDataChannelMessage data) {
  //     LogUtil.d("datachennel :onMessage");
  //     LogUtil.d(channel.label);
  //     LogUtil.d(channel.id);
  //     onDataChannelMessage(data);
  //   };
  // }

  Future<void> _createDataChannel(HanetWebRTCMultipleSession session, {String label = 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..maxRetransmits = 30;
    RTCDataChannel channel = await session.pc!.createDataChannel(label, dataChannelDict);
    channel.onDataChannelState = (state) {
      var lable1 = channel.label;
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        session.dc = channel;
        var request = {"title": "config_get"};
        var message = _encoder.convert(request);
        print('_send_datachennel_msg: $message');
        session.dc?.send(RTCDataChannelMessage(message));
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {}

      print('_addDataChannel :: $lable1 onDataChannelState: $state');
    };
    channel.onMessage = (data) {
      if (data.isBinary) {
      } else {
        onDataChannelTxtMessage(session, data.text);
      }
    };
  }

  // onDataChannelMessage(RTCDataChannelMessage data) async {
  //   if (data.isBinary) {
  //   } else {
  //     onDataChannelTxtMessage(data.text);
  //   }
  // }

  onDataChannelTxtMessage(HanetWebRTCMultipleSession session, message) async {
    print('ondatachennel Message recv $message');
  }

  /// WebRTC Message Handler End
  /// ******************************************************

  @override
  void dispose() {
    _socket?.close();
    eventBus.off(_sendMsgEvent);
    eventBus.off(_delSessionMsgEvent);
    eventBus.off(_newSessionMsgEvent);
    eventBus.off(_recvMsgEvent);
    super.dispose();
  }

  /// ******************************************************
  /// Widget util function Start
  _send(event, data) {
    var request = <String, dynamic>{"eventName": event, "data": data};
    _socket?.send(_encoder.convert(request));
  }

  Future<void> _initEventBus() async {
    _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
      LogUtil.d('_recvMsgEvent: ${event.msg}');
      onMessage(event.msg);
    });

    _sendMsgEvent = eventBus.on<SendMsgEvent>((event) {
      LogUtil.d('_sendMsgEvent: ${event.event} - ${event.data}');
      _send(event.event, event.data);
    });

    _delSessionMsgEvent = eventBus.on<DeleteSessionMsgEvent>((event) {
      var session = _sessions.remove(event.msg);
      LogUtil.d('remove session $session');
    });

    _newSessionMsgEvent = eventBus.on<NewSessionMsgEvent>((event) {
      _sessions[event.msg] = event.msg;
    });
  }

  int compare(String str1, String str2) {
    var res = Comparable.compare(str1, str2);
    return res;
  }

  Future<void> _closePeerConnection(HanetWebRTCMultipleSession session) async {
    if (session._localStream != null) {
      session._localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await session._localStream!.dispose();
      session._localStream = null;
    }

    await session.dc?.close();
    await session.pc?.close();
    await session.pc?.dispose();
    session.dc = null;
    session.pc = null;
    print('_closePeerConnection');
  }

  void closeSession(HanetWebRTCMultipleSession session) async {
    sendDisconnected(session);
    await _closePeerConnection(session);
  }

  void sendDisconnected(HanetWebRTCMultipleSession session) {
    _webSocketSend('__disconnected', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid
    });
  }

  void close() async {
    print('Close');
    for (var i = 0; i < _sessions.length; i++) {
      sendDisconnected(_sessions[i]);
      await _closePeerConnection(_sessions[i]);
    }

    //await _websocket_send_playdisconnect_msg();
  }

  /// Widget util function End
  /// ******************************************************
  _onVideoChick(HanetWebRTCMultipleSession session) {
    setState(() {
      for (var i = 0; i < _sessions.length; i++) {
        HanetWebRTCMultipleSession se = _sessions[i];
        if (compare(se.sid, session.sid) == 0) {}
      }
    });
  }

  Container _buildItem(HanetWebRTCMultipleSession session) => Container(
        child: GestureDetector(
          child: Container(
            height: 120,
            margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
            child: RTCVideoView(session.remoteRenderer),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.fromBorderSide(BorderSide(width: 1, color: Colors.grey, style: BorderStyle.solid)),
            ),
          ),
          onTap: () {
            _onVideoChick(session);
          },
        ),
      );

  Widget _buildVideoView() {
    return Container(
        color: Colors.black, // Always black background
        margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: GridView.count(
            crossAxisCount: widget.showRowVideoWindow,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
            childAspectRatio: 16 / 9,
            children: _showsessions.map((session) => _buildItem(session)).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black, // Always black background
      child: Stack(
        children: [Positioned.fill(child: _buildVideoView())],
      ),
    );
  }
}
