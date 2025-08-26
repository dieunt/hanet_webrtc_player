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

import 'package:flutter/material.dart';

typedef BuildWidget = Widget Function();

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

class RealRemotePlayer extends StatefulWidget {
  static String tag = 'Real Remote Player';
  final String peerId;
  final String selfId;
  final bool usedatachannel;

  RealRemotePlayer(
      {required this.selfId,
      required this.peerId,
      required this.usedatachannel});

  @override
  _RealRemotePlayerState createState() => _RealRemotePlayerState();
}

class _RealRemotePlayerState extends State<RealRemotePlayer> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  String? _selfId;
  String? _peerId;
  bool _dataChannelOpened = false;
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isStartOffer = false;
  bool _inCalling = false;
  bool _remotevideo = true;
  bool _showremotevideo = false;
  bool _usedatachannel = false;

  bool _mute = false;
  bool _speek = false;
  bool _inited = false;

  bool _recording = false;
  double _playindex = 0;
  bool _slider_change = false;
  bool _playing = false;

  List<VideoInfo> _videoList = [];
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  RTCDataChannel? _dataChannel;
  Session? _session;
  Timer? _timer;
  var _recvMsgEvent;

  // ignore: unused_element
  _RealRemotePlayerState();
  GlobalKey<PartRefreshWidgetState> globalKey = new GlobalKey();
  @override
  initState() {
    super.initState();
    if (_inited == false) {
      _inited = true;
      _selfId = widget.selfId;
      _peerId = widget.peerId;
      _usedatachannel = widget.usedatachannel;
      _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
        _signaling?.onMessage(event.msg);
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
        _showremotevideo = true;
      });
    };
    _remoteRenderer.onResize = () {};
  }

  @override
  deactivate() {
    super.deactivate();
    _timer?.cancel();
    eventBus.off(_recvMsgEvent);
    _signaling?.close();
    _remoteRenderer.dispose();
  }

/*
  函数 ：初始化 
  注 ：生成一个 Signaling 类，并实现相应回调函数

*/
  void _initWebrtc() async {
    _signaling ??= Signaling(widget.selfId, widget.peerId, false, true);
    _signaling?.onSendSignalMessge = (String eventName, dynamic data) {
      eventBus.emit(SendMsgEvent(eventName, data));
    };
    /*
       注：信令发送"__connect",返回设备状态后回调，这个时候可以跟句客户端状态发送 offer
     */
    _signaling?.onSessionCreate =
        (String sessionId, String peerId, OnlineState state) {
      // print('onSessionCreateMessge sessionId = $sessionId   peerId = $peerId   $state');
      if (state == OnlineState.OnLine) {
        if (_isStartOffer == true) {
          _invitePeer(sessionId, peerId);
        } else {
          _callPeer(sessionId, peerId);
        }
      }
    };
    /*
      注：信号状态（在本例子，信令通过websocket 该装填基本上没有用）
    */
    _signaling?.onSignalingStateChange = (SignalingState state) {
      switch (state) {
        case SignalingState.ConnectionClosed:
        case SignalingState.ConnectionError:
        case SignalingState.ConnectionOpen:
          break;
      }
    };
    _signaling?.onRedordState = (Session session, RecordState state) {
      if (state == RecordState.Redording) {
        setState(() {
          _recording = true;
        });
      } else if (state == RecordState.RecordClosed) {
        setState(() {
          _recording = false;
        });
      }
    };

    /*
    注： 呼叫状态
    */
    _signaling?.onCallStateChange = (Session session, CallState state) {
      switch (state) {
        case CallState.CallStateNew:
          eventBus.emit(NewSessionMsgEvent(session.sid));
          setState(() {
            _session = session;
            _inCalling = true;
          });

          break;
        case CallState.CallStateBye:
          eventBus.emit(DeleteSessionMsgEvent(session.sid));
          setState(() {
            _remoteRenderer.srcObject = null;
            _inCalling = false;
            _session = null;
          });

          _hangUp();
          break;
        case CallState.CallStateInvite:
        case CallState.CallStateConnected:
        case CallState.CallStateRinging:
      }
    };
    /*
       注： 本地流创建回调，如果需要显示，可以添加相应的显示控件和设置播放源
    */
    _signaling?.onLocalStream = ((stream) {
      stream.getAudioTracks().forEach((track) {
        _mute = track.enabled;

        print(
            'onLocalStream getAudioTracks track ++++++++++++++++++++++++++: ${track.enabled}');
      });
    });
    /*
       注： 添加远程流，这个时候可以把播放源设置成这个远程流
    */
    _signaling?.onAddRemoteStream = ((Session session, stream) {
      stream.getVideoTracks().forEach((track) {
        _remotevideo = true;
      });
      stream.getAudioTracks().forEach((track) {
        _speek = track.enabled;
        track.enableSpeakerphone(true);
      });
      _remoteRenderer.srcObject = stream;
    });
    /*
      注： 移除远程远程流,这个时候可以把显示源设置成空，多个流的情况，可以先判断一下播放源跟移除流是否一样，再设置成空
    */
    _signaling?.onRemoveRemoteStream = ((Session session, stream) {
      _remoteRenderer.srcObject = null;
    });
    _signaling?.onSessionRTCConnectState =
        (Session session, RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          _session == session) {
        print('onSessionRTCConnectState -----------: $state');
      }
    };

    /*
       注：回调创建的DataChannel 
    */
    _signaling?.onDataChannel = (Session session, channel) {
      _dataChannel = channel;
    };
    /*
       注：DataChannel 状态回调 必须在 RTCDataChannelState.RTCDataChannelOpen 后才能通过datachannel 发送数据
    */
    _signaling?.onDataChannelState =
        (Session session, RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        setState(() {
          _dataChannelOpened = true;
        });
        _send_getfilelists_msg(session);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        setState(() {
          _dataChannelOpened = false;
        });
      }
    };
    /*
      注 接收到通过DataChannel 发送过来的消息
    */
    _signaling?.onDataChannelMessage =
        (Session session, dc, RTCDataChannelMessage data) {
      if (data.isBinary) {
        print('Got binary [' + data.binary.toString() + ']');
      } else {
        //print('Got text [' + data.text + ']');
        onDataChannelTxtMessage(data.text);
      }
    };
    /*
       注： 接收到通过信令通道发来的消息
    */
    _signaling?.onRecvSignalingMessage = (Session session, String message) {
      print('Got Signaling  Message [' + message + ']');
    };

    /* 
      注：发送'__connect'信令，获取目标设备在线设备，并初始化 _iceServers
    */
    _signaling?.connect();
  }

  // ignore: non_constant_identifier_names
  _send_getfilelists_msg(Session session) {
    _send_datachennel_msg('__play', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {
            "getfilelist": {
              "starttime": "2022-08-31 00:00:00",
              "endtime": "2022-08-31 23:59:00"
            }
          }
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_remote_play_open_msg(Session session, String file) {
    _send_datachennel_msg('__play', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"open": file}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_remote_play_play_msg(Session session) {
    _send_datachennel_msg('__play', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"start": 0}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_remote_play_seek_msg(Session session, int index) {
    _send_datachennel_msg('__play', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"seek": index}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_remote_play_stop_msg(Session session) {
    _send_datachennel_msg('__play', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"stop": "cancel"}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_remote_play_pause_msg(Session session, bool pause) {
    _send_datachennel_msg('__play', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
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
      _dataChannel?.send(RTCDataChannelMessage(_encoder.convert(request)));
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
            if (key == "getfilelist") {
              Map<String, dynamic> getfilelists = value;
              getfilelists.forEach((key_getfile, value_getfile) {
                if (key_getfile == "code") {
                } else if (key_getfile == "state") {
                } else if (key_getfile == "filelists") {
                  List<dynamic> filelists = value_getfile;
                  filelists.forEach((item) {
                    Map<String, dynamic> fileitem = item;
                    if (_videoList.length < 7) {
                      setState(() {
                        _videoList.add(VideoInfo.fromJson(fileitem));
                      });
                    } else {
                      _videoList.add(VideoInfo.fromJson(fileitem));
                    }
                  });
                }
              });
            } else if (key == "open") {
              _playindex = 0;
              globalKey.currentState?.update();
              Map<String, dynamic> openvalue = value;
              openvalue.forEach((key_open, value_open) {
                // print("k=$key_open,v=$value_open");
              });
              _send_remote_play_play_msg(_session!);
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

  /*
     函数 ： 发起呼叫  
     注：  生成一个会话并创建 RTCPeerConnection 并发起Offer
  */
  _invitePeer(String sessionId, String peerId) async {
    if (peerId != _selfId) {
      _signaling?.invite(sessionId, peerId, true, true, false, false, true,
          "play", "", "admin", "123456");
    }
  }

  _callPeer(String sessionId, String peerId) async {
    if (peerId != _selfId) {
      _signaling?.startcall(sessionId, peerId, true, true, false, false, true,
          "play", "", "admin", "123456");
    }
  }

/*
    函数 ： 挂起通话
    注： 发送一个__disconnect 消息 并返回上一页面
*/
  _hangUp() {
    _timer?.cancel();
    if (_session != null) {
      _signaling?.bye(_session!.sid);
    }
    Navigator.pop(context, true);
  }

  _handlerecord() {
    if (_inCalling) {
      if (_recording == false) {
        if (_session != null) {
          _signaling?.startRecord(_session!.sid);
        }
      } else {
        if (_session != null) {
          _signaling?.stopRecord(_session!.sid);
        }
      }
    } else {
      //print('startRecord -----------------------_inCalling = $_inCalling');
    }
  }

  _handlcapture() {
    if (_inCalling) {
      if (_session != null) {
        _signaling?.captureFrame(_session!.sid);
      }
    }
  }

  /*
    函数： 关闭所有声音
*/
  _switchVolume() {
    if (_inCalling) {
      setState(() {
        _speek = !_speek;
      });
      _signaling?.muteAllSpeek(_speek);
    }
  }

/*
    函数： 静音
*/
  _muteMic() {
    if (_inCalling) {
      setState(() {
        _mute = !_mute;
      });
      _signaling?.muteMic(_mute);
    }
  }

  /*
  函数： 通过信令通道发送消息
  注： 
  */
  _postmessage(String message) async {
    if (_session != null) {
      _signaling?.postmessage(_session!.sid, message);
    }
  }

  _onVideoInfoChick(VideoInfo videoInfo, int index) {
    // print('_onVideoInfoChick ----------------------- = $index');
    if (_session != null) {
      _send_remote_play_open_msg(_session!, videoInfo.fileName!);
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
          if (_session != null) {
            _send_remote_play_seek_msg(_session!, _playindex.toInt());
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
          appBar: AppBar(
            title: Text('Real Remote Player' +
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
