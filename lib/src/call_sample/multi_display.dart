// ignore_for_file: avoid_print, prefer_typing_uninitialized_variables
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
// import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
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

class MultiDisplaySession {
  MultiDisplaySession({required this.sid, required this.pid, required this.remoteRenderer, required this.mediarecoder});
  String pid;
  String sid;
  String videofilepath = "";
  bool _focus = false;
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  RTCVideoRenderer remoteRenderer;
  MediaRecorder mediarecoder;
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc.qq-kan.com:3478'},
    ]
  };
  List<RTCIceCandidate> remoteCandidates = [];
  bool _domainname = false;
  Map<String, dynamic> _domainnameiceServers = {
    'iceServers': [
      {'url': 'stun:webrtc.qq-kan.com:3478'},
    ]
  };
  bool _dataChannelOpened = false;

  bool _inCalling = false;
  bool _mute = false;
  bool _speek = false;

  bool _inited = false;

  bool _recording = false;
  MediaStreamTrack? _remotevideotrack;
  MediaStreamTrack? _remoteaudiotrack;

  bool audio = false;
  bool video = false;
  bool dataChannel = false;

  MediaStream? _localStream;
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

class MultiDisplay extends StatefulWidget {
  static String tag = 'Could Player';
  final String peerId;
  final String selfId;
  final bool usedatachannel;

  MultiDisplay({required this.selfId, required this.peerId, required this.usedatachannel});

  @override
  _MultiDisplayState createState() => _MultiDisplayState();
}

class _MultiDisplayState extends State<MultiDisplay> {
  String? _selfId;
  String? _peerId;
  String? _sid;

  bool _usedatachannel = false;

  bool _inited = false;

  bool _inCalling = false;
  bool _mute = false;
  bool _speek = false;
  bool _recording = false;
  int _showRowVideoWindow = 2;
  int _showVideoWindow = 8;

  final List<MultiDisplaySession> _sessions = [];
  final List<MultiDisplaySession> _showsessions = [];
  String focusSessionId = "";

  final JsonEncoder _encoder = JsonEncoder();
  final JsonDecoder _decoder = JsonDecoder();

  // Map<String, MultiDisplaySession> _sessions = {};

/*
流程
     
*/
  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
      {'googCpuOveruseDetection': false},
      {'googSuspendBelowMinBitrate': true},
    ]
  };

  String get sdpSemantics => WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  var _recvMsgEvent;

  // ignore: unused_element
  _MultiDisplayState();
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

      _initWebrtc();
    }
  }

  /*
    注：初始化显示控件
  */
  initRenderers(RTCVideoRenderer remoteRenderer) async {
    await remoteRenderer.initialize();
    remoteRenderer.onFirstFrameRendered = () {
      setState(() {
        // _showremotevideo = true;
      });
    };

    remoteRenderer.onResize = () {};
  }

  UninitRenderers(RTCVideoRenderer remoteRenderer) async {
    remoteRenderer.dispose();
  }

  @override
  deactivate() {
    super.deactivate();
    close();
    eventBus.off(_recvMsgEvent);

    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession sess = _sessions[i];
      UninitRenderers(sess.remoteRenderer);
    }
  }

/*
  函数 ：初始化 websocket_send_getfilelists_msg();
  注 ：生成一个 Signaling 类，并实现相应回调函数

*/
  void _initWebrtc() {
    _sessions.clear();
/*
    _createSession(
        sessionId: randomNumeric(32),
        peerId: "BWCX-00-3V91-8RWB-00000009",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: true);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "BWCX-00-4KTT-29GW-00000003",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "BWCX-00-DNWC-RVR8-00000011",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "BWCX-00-NTAN-8F5D-00000033",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);
        
    _createSession(
        sessionId: randomNumeric(32),
        peerId: "BWCX-00-4KTT-29GW-00000003",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: true);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "BWCX-00-NTAN-8F5D-00000033",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);
  */

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-X54T-257U-00003572",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: true);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-X54T-257U-00003572",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-WTSN-9S3D-00000727",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-WTSN-9S3D-00000727",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);
    /*
    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-LR8I-DX8T-00000988",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);
    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-LR8I-DX8T-00000988",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-LR8I-DX8T-00000988",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-LR8I-DX8T-00000988",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);


    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-KVFH-TAX2-00000001",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-FCC6-Z3ND-00000002",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "RHZL-00-LR8I-DX8T-00000988",
        remoteRenderer: RTCVideoRenderer(),
        mediarecoder: MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);
*/
    _createSession(
        sessionId: randomNumeric(32),
        peerId: "",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    _createSession(
        sessionId: randomNumeric(32),
        peerId: "",
        remoteRenderer: new RTCVideoRenderer(),
        mediarecoder: new MediaRecorder(),
        audio: true,
        video: true,
        dataChannel: true,
        focus: false);

    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession sess = _sessions[i];
      initRenderers(sess.remoteRenderer);
    }

    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession sess = _sessions[i];
      if (sess.pid.length > 0) {
        Connect(sess);
      }
    }
  }

  int compare(String str1, String str2) {
    var res = Comparable.compare(str1, str2);
    return res;
  }

  void onMessage(message) async {
    print('onMessage :$message');

    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    var sessionId = data['sessionId'];
    var peerId = data['from'];
    switch (eventName) {
      case "_create":
        {
          for (var i = 0; i < _sessions.length; i++) {
            MultiDisplaySession sess = _sessions[i];
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
      case "_call":
        {}
        break;
      case "_offer":
        {
          for (var i = 0; i < _sessions.length; i++) {
            MultiDisplaySession sess = _sessions[i];
            if (sess.sid == sessionId) {
              var sdp = data['sdp'];
              LogUtil.d("_offer $sdp");
              await _createPeerConnectionByOffer(sess, true, true, true, sdp);
            }
          }
        }
        break;
      case "_answer":
        {}
        break;
      case "_ice_candidate":
        {
          for (var i = 0; i < _sessions.length; i++) {
            MultiDisplaySession sess = _sessions[i];
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
      case "_disconnected":
        {
          for (var i = 0; i < _sessions.length; i++) {
            MultiDisplaySession sess = _sessions[i];
            if (sess.sid == sessionId) {
              closeSession(sess);
            }
          }
        }
        break;
      case "_session_failed":
        {
          for (var i = 0; i < _sessions.length; i++) {
            MultiDisplaySession sess = _sessions[i];
            if (sess.sid == sessionId) {
              closeSession(sess);
            }
          }
        }
        break;
      case '_post_message':
        break;
      case '_connectinfo':
        print('onMessage recv $message');
        break;
      case "_ping":
        {}
        break;
      default:
        break;
    }
  }

  websocket_send(eventName, data) {
    eventBus.emit(SendMsgEvent(eventName, data));
  }

  Future<void> Connect(MultiDisplaySession session) async {
    websocket_send('__connectto', {
      'sessionId': session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
    });
  }

  void startCall(MultiDisplaySession session) {
    var datachanneldir = 'true';
    var audiodir = 'sendrecv';
    var videodir = 'recvonly';

    websocket_send('__call', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      "mode": "live",
      "source": "MainStream",
      "datachannel": datachanneldir,
      "audio": audiodir,
      "video": videodir,
      "user": "admin",
      "pwd": "123456",
      "iceservers": _encoder.convert(session._iceServers)
    });
  }

  void senddisconnected(MultiDisplaySession session) {
    websocket_send('__disconnected', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid
    });
  }

  Future<void> _createDataChannel(MultiDisplaySession session, {label = 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..maxRetransmits = 30;
    RTCDataChannel channel = await session.pc!.createDataChannel(label, dataChannelDict);
    channel.onDataChannelState = (state) {
      var lable1 = channel.label;
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        session._dataChannelOpened = true;
        session.dc = channel;
        var request = {"title": "config_get"};
        var message = _encoder.convert(request);
        print('_send_datachennel_msg: $message');
        session!.dc?.send(RTCDataChannelMessage(message));
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        session._dataChannelOpened = false;
      }

      print('_addDataChannel :: $lable1 onDataChannelState: $state');
    };
    channel.onMessage = (data) {
      if (data.isBinary) {
      } else {
        onDataChannelTxtMessage(session, data.text);
      }
    };
  }

  // ignore: non_constant_identifier_names
  send_datachennel_msg(MultiDisplaySession? session, event, data) {
    if (session!._dataChannelOpened) {
      var request = new Map();
      request["eventName"] = event;
      request["data"] = data;
      var message = _encoder.convert(request);
      print('_send_datachennel_msg: $message');
      session!.dc?.send(RTCDataChannelMessage(message));
    }
  }

  void onDataChannelTxtMessage(MultiDisplaySession? session, message) async {
    print('ondatachennel Message recv $message');
  }

  Future<MultiDisplaySession> _createSession(
      {required String sessionId,
      required String peerId,
      required RTCVideoRenderer remoteRenderer,
      required MediaRecorder mediarecoder,
      required bool audio,
      required bool video,
      required bool dataChannel,
      required bool focus}) async {
    var newSession =
        MultiDisplaySession(sid: sessionId, pid: peerId, remoteRenderer: remoteRenderer, mediarecoder: mediarecoder);

    newSession.audio = audio;
    newSession.video = false;
    newSession.dataChannel = dataChannel;

    _sessions.add(newSession);
    if (_showsessions.length < _showVideoWindow) {
      _showsessions.add(newSession);
    }
    newSession._focus = focus;
    if (focus) {
      focusSessionId = sessionId;
      newSession._speek = _speek;
      newSession._mute = _mute;
    } else {
      newSession._speek = _speek;
      newSession._mute = _mute;
    }
    print('create Session : ' + sessionId);
    return newSession;
  }

  Future<void> _createAnswer(MultiDisplaySession? se, RTCPeerConnection pc) async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s = await pc.createAnswer(dcConstraints);

      await pc.setLocalDescription(s);

      //LogUtil.d("_createAnswer ${s.sdp}");
      websocket_send('__answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': se!.sid,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': se.pid
      });
    } catch (e) {
      print(e.toString());
    }
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

  Future<RTCPeerConnection> _createPeerConnectionByOffer(
      MultiDisplaySession session, bool audio, bool video, bool dataChannel, String sdp) async {
    //print(_iceServers);
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

    if (session.audio || session.video) {
      MediaStream localstream = await createLocalStream(true, false, true);
      if (localstream != null) {
        session._localStream = localstream;

        switch (sdpSemantics) {
          case 'plan-b':
            if (localstream != null) {
              await peerConnection.addStream(localstream);
            }

            break;
          case 'unified-plan':
            // Unified-Plan
            if (localstream != null) {
              localstream.getTracks().forEach((track) {
                track.enabled = session._mute;
                peerConnection.addTrack(track, localstream);
              });
            }
            break;
        }
      }
    }

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
          () => websocket_send('__ice_candidate', {
                'sessionId': session!.sid,
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
        session._inCalling = true;
        if (session.sid == focusSessionId) {
          setState(() {
            _inCalling = true;
          });
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        session._inCalling = false;
        if (session.sid == focusSessionId) {
          setState(() {
            _inCalling = false;
          });
        }
      }

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
        audioTrack.enabled = session._speek;
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
        track.enabled = session._speek;
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
    peerConnection.onDataChannel = (channel) {
      channel.onDataChannelState = (state) {
        var lable1 = channel.label;
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          session._dataChannelOpened = true;
          session.dc = channel;
        } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
          session._dataChannelOpened = false;
        }

        print('_addDataChannel :: $lable1 onDataChannelState: $state');
      };
      channel.onMessage = (data) {
        if (data.isBinary) {
        } else {
          onDataChannelTxtMessage(session, data.text);
        }
      };
    };

    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, "offer"));
    await _createAnswer(session, peerConnection);

    await _createDataChannel(session);

    if (session.remoteCandidates.isNotEmpty) {
      session.remoteCandidates.forEach((candidate) async {
        // print('addCandidate------------------- :$candidate');
        await peerConnection.addCandidate(candidate);
      });
      session.remoteCandidates.clear();
    }

    return peerConnection;
  }

  Future<void> _closePeerConnection(MultiDisplaySession session) async {
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

  void closeSession(MultiDisplaySession session) async {
    senddisconnected(session);
    await _closePeerConnection(session);
    ;
  }

  void close() async {
    print('Close');
    for (var i = 0; i < _sessions.length; i++) {
      await stopRecord(_sessions[i]);
      senddisconnected(_sessions[i]);
      await _closePeerConnection(_sessions[i]);
    }

    //await _websocket_send_playdisconnect_msg();
  }

/*
    函数 ： 挂起通话
    注： 发送一个__disconnect 消息 并返回上一页面
*/
  _hangUp() {
    close();

    Navigator.pop(context, true);
  }

  Future<void> muteLocalStreamSession(MultiDisplaySession sess) async {
    if (sess._inCalling == true) {
      List<RTCRtpSender> senders = await sess.pc!.getSenders();
      for (var i = 0; i < senders.length; i++) {
        RTCRtpSender sender = senders[i];
        if (sender.track != null && sender.track!.kind == "audio") {
          setState(() {
            _mute = sess._mute = !sess._mute;
          });
          sender.track!.enabled = sess._mute;
          print('muteLocalStreamSession track ${sess.sid} ------------------------: ${sender.track}');
        }
      }
    }
  }

  Future<void> muteSpeekSession(MultiDisplaySession sess) async {
    if (sess._inCalling == true) {
      List<RTCRtpReceiver> receivers = await sess.pc!.getReceivers();
      for (var i = 0; i < receivers.length; i++) {
        RTCRtpReceiver receive = receivers[i];
        if (receive.track!.kind == "audio") {
          setState(() {
            _speek = sess._speek = !sess._speek;
          });
          receive.track!.enabled = sess._speek;
          print('muteSpeekSession track ${sess.sid} ------------------------: ${receive.track}');
        }
      }
    }
  }

  Future<void> EnableSpeekSession(MultiDisplaySession sess, bool enable) async {
    if (sess._inCalling == true) {
      List<RTCRtpReceiver> receivers = await sess.pc!.getReceivers();
      for (var i = 0; i < receivers.length; i++) {
        RTCRtpReceiver receive = receivers[i];
        if (receive.track!.kind == "audio") {
          receive.track!.enabled = sess._speek;
          setState(() {
            sess._speek = enable;
            _speek = enable;
          });
          print('EnableSpeekSession track ${sess.sid} ------------------------: ${receive.track}');
        }
      }
    }
  }

  Future<void> startRecord(MultiDisplaySession sess) async {
    if (sess._recording == false && sess._inCalling == true) {
      print('startRecord ------------------------${sess.sid}');
      try {
        var id = sess.pc!.getPeerConnectionId();
        print('startRecord peerconnectid id : $id');
        var appDocDir;
        if (Platform.isIOS) {
          appDocDir = await getApplicationDocumentsDirectory();
        } else if (Platform.isAndroid) {
          appDocDir = await getExternalStorageDirectory();
        } else {
          return;
        }
        String peerconnectid = "";
        peerconnectid = (id) as String;
        String appDocPath = appDocDir!.path;
        print('startRecord peerconnectid : $peerconnectid');
        print('startRecord appDocPath : $appDocPath');
        DateTime now = DateTime.now();
        String strtime = now.toString().replaceAll(" ", "").replaceAll(".", "").replaceAll("-", "").replaceAll(":", "");
        String recordFilepath = "$appDocPath" + "/" + strtime + ".mp4";
        List<RTCRtpReceiver>? receivers = await sess.pc!.getReceivers();
        print('startRecord track ------------------------: ${recordFilepath}');
        for (int i = 0; i < receivers.length; i++) {
          RTCRtpReceiver receive = receivers[i];
          print('startRecord track ------------------------: ${receive.track}');
          if (receive.track!.kind == "video") {
            RecorderAudioChannel audiochannel = RecorderAudioChannel.OUTPUT;
            //sess.mediarecoder = new MediaRecorder();
            sess.mediarecoder.start(3, recordFilepath, peerconnectid,
                videoTrack: receive.track, audioTrack: sess._remoteaudiotrack, audioChannel: audiochannel);
            sess.videofilepath = recordFilepath;
            sess._recording = true;
            setState(() {
              _recording = true;
            });
            break;
          }
        }
        ;
      } catch (err) {
        print(err);
      }
    } else {
      print('startRecord  is recording');
    }
  }

  /*
    停止录像
  */
  Future<void> stopRecord(MultiDisplaySession sess) async {
    print('stopRecord  -------------------------------------------${sess.sid}');
    if (sess._recording == true) {
      print('stopRecord ');
      await sess.mediarecoder.stop();
      sess._recording = false;
      if (sess.videofilepath.length > 0) {
        // final result = await ImageGallerySaver.saveFile(sess.videofilepath);
        // if (result['isSuccess'] == true) {
        //   await deleteFile(sess.videofilepath);
        // }
        sess.videofilepath = "";
      }

      setState(() {
        _recording = false;
      });
      print('stopRecord  end');
    }
  }

  Future<int> deleteFile(String filename) async {
    try {
      final file = File(filename);

      await file.delete();
      return 1;
    } catch (e) {
      return 0;
    }
  }

  Future<void> captureFrame(MultiDisplaySession sess) async {
    if (sess._inCalling == true) {
      try {
        var appDocDir;
        if (Platform.isIOS) {
          appDocDir = await getApplicationDocumentsDirectory();
        } else if (Platform.isAndroid) {
          appDocDir = await getExternalStorageDirectory();
        } else {
          return;
        }
        String appDocPath = appDocDir!.path;
        print('captureFrame appPath: ' + appDocPath);
        print('captureFrame session id: ' + sess.sid);
        print('captureFrame peerConnection id: ' + sess.pc!.getPeerConnectionId());
        DateTime now = DateTime.now();
        String strtime = now.toString().replaceAll(" ", "").replaceAll(".", "").replaceAll("-", "").replaceAll(":", "");
        String captureFilepath = "$appDocPath" + "/" + strtime + ".jpg";
        List<RTCRtpReceiver>? receivers = await sess.pc?.getReceivers();
        for (int i = 0; i < receivers!.length; i++) {
          RTCRtpReceiver receive = receivers[i];
          if (receive.track!.kind!.isNotEmpty) {
            if (receive.track!.kind!.compareTo("video") == 0) {
              if (sess._remotevideotrack!.id == receive.track!.id) {
                print('captureFrame track : ${receive.track!.kind}');
                print('captureFrame track id: ${receive.track!.id}');
                await receive.track!.captureFrame(captureFilepath);

                print('captureFrame track :  $captureFilepath');
                openImage(captureFilepath);
              }
            }
          }
        }
      } catch (err) {
        print(err);
      }
    }
  }

  openImage(var filePath) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("打开图片"),
          content: Container(
            child: Image.file(File(filePath)),
          ),
          actions: [
            TextButton(
              child: Text("取消"),
              onPressed: () => {deleteFile(filePath), Navigator.of(context).pop()},
            ),
            TextButton(
              child: Text("确定"),
              onPressed: () => {deleteFile(filePath), Navigator.of(context).pop()},
            ),
          ],
        );
      },
    );
  }

  Future<void> writeToFile(ByteData data, String path) async {
    final buffer = data.buffer;
    await File(path).writeAsBytes(buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  _handlerecord() {
    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession se = _sessions[i];
      if (compare(se.sid, focusSessionId) == 0) {
        if (se!._recording == false) {
          startRecord(se);
        } else {
          stopRecord(se);
        }
        break;
      }
    }
  }

  _switchVolume() {
    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession se = _sessions[i];
      if (compare(se.sid, focusSessionId) == 0) {
        muteSpeekSession(se);
        break;
      }
    }
  }

  _muteMic() {
    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession se = _sessions[i];
      if (compare(se.sid, focusSessionId) == 0) {
        muteLocalStreamSession(se);
        break;
      }
    }
  }

  _handlcapture() {
    for (var i = 0; i < _sessions.length; i++) {
      MultiDisplaySession se = _sessions[i];
      if (compare(se.sid, focusSessionId) == 0) {
        print('captureFrame focusSessionId: ' + focusSessionId);
        print('captureFrame sid: ' + se.sid);
        captureFrame(se);
        break;
      }
    }
  }

  _onVideoChick(MultiDisplaySession session) {
    setState(() {
      for (var i = 0; i < _sessions.length; i++) {
        MultiDisplaySession se = _sessions[i];
        if (compare(se.sid, session.sid) == 0) {
          focusSessionId = session.sid;
          _inCalling = session._inCalling;
          _recording = session._recording;
          se._focus = true;
          _speek = session._speek;
          _mute = session._mute;
          if (se._inCalling && _speek) {
            // EnableSpeekSession(se, true);
          }
        } else {
          se._focus = false;
          // EnableSpeekSession(se, false);
        }
      }
    });
  }

  _onVideoDoubleChick(MultiDisplaySession session) {
    setState(() {
      if (_showRowVideoWindow == 2) {
        _showRowVideoWindow = 1;

        _showsessions.clear();
        _showsessions.add(session);

        for (var i = 0; i < _sessions.length; i++) {
          MultiDisplaySession se = _sessions[i];
          if (compare(se.sid, session.sid) == 0) {
            se._focus = true;
            focusSessionId = session.sid;
            _inCalling = session._inCalling;
            _recording = session._recording;
          } else {
            se._focus = false;
          }
        }
      } else {
        _showRowVideoWindow = 2;
        _showsessions.clear();
        for (var i = 0; i < _sessions.length; i++) {
          MultiDisplaySession se = _sessions[i];
          if (_showsessions.length < _showVideoWindow) {
            _showsessions.add(se);
          }
        }
      }
    });
  }

  Container _buildItem(MultiDisplaySession session) => Container(
        child: GestureDetector(
          child: Container(
            height: 120,
            margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
            child: RTCVideoView(session.remoteRenderer),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.fromBorderSide(
                  BorderSide(width: 1, color: session._focus ? Colors.red : Colors.grey, style: BorderStyle.solid)),
            ),
          ),
          onTap: () {
            _onVideoChick(session);
          },
          onDoubleTap: () {
            _onVideoDoubleChick(session);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
          appBar: AppBar(
            title: Text('MultiDisplay' + (_selfId != null ? ' [Your ID ($_selfId)] ' : '')),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: SizedBox(
              width: 300.0,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
                FloatingActionButton(
                  child: const Icon(Icons.video_camera_back),
                  onPressed: _handlerecord,
                  heroTag: 'record',
                  backgroundColor: _inCalling
                      ? _recording
                          ? Colors.pink
                          : Colors.blue
                      : Colors.grey,
                ),
                FloatingActionButton(
                  child: _speek ? const Icon(Icons.volume_off) : const Icon(Icons.volume_up),
                  backgroundColor: _inCalling ? Colors.blue : Colors.grey,
                  onPressed: _switchVolume,
                  heroTag: 'switch_volume',
                ),
                FloatingActionButton(
                  onPressed: _hangUp,
                  tooltip: 'Hangup',
                  heroTag: 'Hangup',
                  child: const Icon(Icons.call_end),
                  backgroundColor: Colors.pink,
                ),
                FloatingActionButton(
                  child: _mute ? const Icon(Icons.mic_off) : const Icon(Icons.mic),
                  backgroundColor: _inCalling ? Colors.blue : Colors.grey,
                  onPressed: _muteMic,
                  heroTag: 'muteMic',
                ),
                FloatingActionButton(
                  child: const Icon(Icons.photo_camera),
                  onPressed: _handlcapture,
                  heroTag: 'capture',
                  backgroundColor: _inCalling ? Colors.blue : Colors.grey,
                )
              ])),
          body: OrientationBuilder(builder: (context, orientation) {
            return Container(
                child: GridView.count(
                    crossAxisCount: _showRowVideoWindow,
                    mainAxisSpacing: 0,
                    crossAxisSpacing: 0,
                    childAspectRatio: 1 / 0.75,
                    children: _showsessions.map((session) => _buildItem(session)).toList()));
          })),
      onWillPop: () {
        //监听到退出按键
        _hangUp();
        return Future<bool>.value(true);
      },
    );
  }
}
