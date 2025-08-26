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

class CouldPlayer extends StatefulWidget {
  static String tag = 'Could Player';
  final String peerId;
  final String selfId;
  final bool usedatachannel;

  CouldPlayer(
      {required this.selfId,
      required this.peerId,
      required this.usedatachannel});

  @override
  _CouldPlayerState createState() => _CouldPlayerState();
}

class _CouldPlayerState extends State<CouldPlayer> {
  String? _selfId;
  String? _peerId;
  String? _sid;
  bool _dataChannelOpened = false;
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _usedatachannel = false;
  String _current_serveraddr = "";
  String _temp_current_serveraddr = "";
  String _temp_current_filename = "";
  String _temp_current_filepath = "";
  String _temp_current_starttime = "";
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
/*
流程
1)     通过 websocket 获取文件列表                                   函数  _websocket_send_getfilelists_msg
                                                                                     |
                                                                                     |
                                                  
2)     通过 点击文件列表  发送 __could_play_call 信令             函数 _websocket_send_playcall_msg


3）    websocket 接收到      _could_play_offer  信令             建立 webrtc PeerConnection  等待 datachennel open 事件


4）    datachennel onopen 事件  通过 datachennel 发送                 函数    _send_could_play_open_msg   


5）    onDataChannelTxtMessage  收到 open 信令  发送   start 信令       函数   _send_could_play_play_msg





7）     
*/
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
  _CouldPlayerState();
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
    _websocket_send_getfilelists_msg();
  }

  void onMessage(message) async {
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];

    switch (eventName) {
      case "_could_getfiles":
        {
          if (data != null) {
            var datamsg = data['message'];
            if (datamsg != null) {
              Map<String, dynamic> fileitem = datamsg;

              setState(() {
                _videoList.add(VideoInfo.fromJson(fileitem));
              });
            }
          }
        }
        break;
      case "_could_play_offer":
        {
          _current_serveraddr = _temp_current_serveraddr;
          var iceServers = data['iceservers'];
          //  print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer iceServers  :$iceServers');
          if (iceServers != null && iceServers.toString().isNotEmpty) {
            _iceServers = _decoder.convert(iceServers);
          }
          var sdp = data['sdp'];
          var peerconnect = await _createPeerConnection(
              audio: true, video: true, dataChannel: true);
          await peerconnect
              .setRemoteDescription(RTCSessionDescription(sdp, "offer"));
          await _createAnswer(peerconnect);
        }
        break;
      case "_could_play_ice_candidate":
        {}
        break;
      case "_could_play_session_disconnected":
        {
          Close();
        }
        break;
      case "_could_play_post_message":
        {}
        break;
      case "_could_play_connectinfo":
        {}
        break;
      case "_could_play_session_failed":
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
      print('_websocket_send: $data');
    eventBus.emit(SendMsgEvent(eventName, data));
  }

  // ignore: non_constant_identifier_names
  _websocket_send_getfilelists_msg() {
    _videoList.clear();
    DateTime now = DateTime.now();
    DateTime start = now.add(new Duration(days: -180));
    DateFormat dateFormat = DateFormat("yyyy-MM-dd HH:mm:ss");
    var endtime = dateFormat.format(now);
    var starttime = dateFormat.format(start);
    _websocket_send('__could_getfiles', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'start': starttime,
      'end': endtime,
      'offset': "0",
      'limit': "20",
    });
  }

  _websocket_send_playcall_msg(String serveraddr) {
    _websocket_send('__could_play_call', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'message': {
        'serveraddr': serveraddr,
      }
    });
  }

  _websocket_send_playdisconnect_msg() {
    _websocket_send('__could_play_disconnected', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
    });
  }

  // ignore: non_constant_identifier_names
  _send_could_play_open_msg(
      String file, String filepath, String starttime, int event) {
    _send_datachennel_msg('__play', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _peerId,
      'to': _peerId,
      'message': {
        "request": [
          {"open": file},
          {"filepath": filepath},
          {"event": event},
          {"starttime": starttime},
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_could_play_play_msg() {
    _send_datachennel_msg('__play', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'message': {
        "request": [
          {"start": 0}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_could_play_seek_msg(int index) {
    _send_datachennel_msg('__play', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'message': {
        "request": [
          {"seek": index}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_could_play_stop_msg() {
    _send_datachennel_msg('__play', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'message': {
        "request": [
          {"stop": "cancel"}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_could_play_pause_msg(bool pause) {
    _send_datachennel_msg('__play', {
      "sessionId": _sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'message': {
        "request": [
          {"pause": pause}
        ]
      }
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
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    if (eventName == "_play") {
      var datamsg = data['message'];
      if (datamsg != null) {
        var datresponse = datamsg['response'];
        //
        List<dynamic> list = datresponse;
        list.forEach((element) {
          Map<String, dynamic> content = element;
          content.forEach((key, value) {
            if (key == "open") {
              _playindex = 0;
              globalKey.currentState?.update();
              Map<String, dynamic> openvalue = value;
              openvalue.forEach((key_open, value_open) {
                // print("k=$key_open,v=$value_open");
              });
              _send_could_play_play_msg();
            } else if (key == "start") {
              _playing = true;
              Map<String, dynamic> startvalue = value;
              startvalue.forEach((key_start, value_start) {
                //  print("k=$key_start,v=$value_start");
              });
            } else if (key == "pause") {
              Map<String, dynamic> pausevalue = value;
              pausevalue.forEach((key_pause, value_pause) {
                // print("k=$key_pause,v=$value_pause");
              });
            } else if (key == "stop") {
              _playing = false;
              Map<String, dynamic> stopvalue = value;
              stopvalue.forEach((key_stop, value_stop) {
                // print("k=$key_stop,v=$value_stop");
                setState(() {
                  _playindex = 0;
                });
              });
            } else if (key == "currentstate") {
              Map<String, dynamic> currentstatevalue = value;
              currentstatevalue.forEach((key_currentstate, value_currentstate) {
                //print("k=$key_currentstate,v=$value_currentstate");
                if (key_currentstate == "position") {
                  Map<String, dynamic> positionvalue = value_currentstate;
                  positionvalue.forEach((key_position, value_position) {
                    if (key_position == "current") {
                      if (!_slider_change) {
                        _playindex = value_position.toDouble();
                        globalKey.currentState?.update();
                      }
                    }
                  });
                }
              });
            }
          });
        });
      }
    }
  }

  Future<void> _createAnswer(RTCPeerConnection peerConnection) async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s =
          await peerConnection.createAnswer(dcConstraints);

      await peerConnection.setLocalDescription(s);

      LogUtil.v("_createAnswer ${s.sdp}");
      _websocket_send('__could_play_answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': _sid,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': _peerId
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
          () => _websocket_send('__could_play_ice_candidate', {
                'sessionId': _sid,
                'sessionType': "flutter",
                'messageId': randomNumeric(32),
                'from': _selfId,
                'to': _peerId,
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
    await _websocket_send_playdisconnect_msg();
    await _closePeerConnection();
  }

  _addDataChannel(RTCDataChannel datachennel) {
    dc = datachennel;
    datachennel.onDataChannelState = (state) {
      var lable1 = datachennel.label;
      print('_addDataChannel :: $lable1 onDataChannelState: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannelOpened = true;
        if (_temp_current_filename.isEmpty == false) {
          _send_could_play_open_msg(
              _temp_current_filename,
              _temp_current_filepath,
              _temp_current_starttime,
              _temp_current_event);
        }
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

  _onVideoInfoChick(VideoInfo videoInfo, int index) {
    // print('_onVideoInfoChick  = $index');
    if (_current_serveraddr == "" ||
        _current_serveraddr.contains(videoInfo.serveraddr!) == false) {
      Close();
      if (_current_serveraddr.isEmpty == false) {
        _sid = randomNumeric(32);
      }
      _temp_current_filename = videoInfo.fileName!;
      _temp_current_event = videoInfo.event!;
      _temp_current_starttime = videoInfo.starttime!;
      _temp_current_serveraddr = videoInfo.serveraddr!;
      _temp_current_filepath = videoInfo.filePath!;
      _websocket_send_playcall_msg(videoInfo.serveraddr!);
    } else {
      if (_current_serveraddr.isEmpty == false &&
          _current_serveraddr.contains(videoInfo.serveraddr!) == true) {
        _send_could_play_open_msg(videoInfo.fileName!, videoInfo.filePath!,
            videoInfo.starttime!, videoInfo.event!);
      } else {}
    }
  }

  Widget getRow(int a) {
    VideoInfo vinfo = _videoList[a];
    return GestureDetector(
      child: Padding(
        padding: EdgeInsets.all(1.0),
        child: ListTile(
          leading:
              Image.memory(Base64Decoder().convert(vinfo.image!.split(',')[1])),
          title: Text(vinfo.fileName!),
          subtitle: Text(vinfo.starttime!),
        ),
      ),
      onTap: () {
        _onVideoInfoChick(vinfo, a);
      },
    );
  }

  Slider _slider() {
    return Slider(
      activeColor: Colors.white,
      value: _playindex,
      max: 100,
      onChanged: (value) {
        _playindex = value;
        globalKey.currentState?.update();
      },
      onChangeStart: (value) {
        // print("onChangeStart : $value");
        _slider_change = true;
        // updateSlider(value, "onChangeStart : $value");
      },
      onChangeEnd: (value) {
        // print("onChangeEnd : $value");
        // updateSlider(value, "onChangeEnd : $value");
        _slider_change = false;
        if (_playing) {
          _send_could_play_seek_msg(_playindex.toInt());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
          appBar: AppBar(
            title: Text('Could Player' +
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
                    Positioned(
                      width: MediaQuery.of(context).size.width,
                      height: 30,
                      bottom: 10,
                      child: PartRefreshWidget(globalKey, () {
                        return _slider();
                      }),

                      //right: 10,
                    ),
                  ]),
                ),
                Positioned(
                  left: 0.0,
                  right: 0.0,
                  top: 200.0,
                  bottom: 0.0,
                  child: ListView.builder(
                    itemBuilder: (BuildContext context, int a) {
                      return getRow(a);
                    },
                    itemCount: _videoList.length,
                  ),
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
