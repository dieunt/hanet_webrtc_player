// ignore_for_file: avoid_print, prefer_typing_uninitialized_variables

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'camera_seting.dart';
import 'dart:core';
import 'dart:ui' as UI;
import 'dart:async';
import 'dart:typed_data';
import 'signaling.dart';
import 'event_bus_util.dart';
import 'event_message.dart';

class RealAudioJpgVideo extends StatefulWidget {
  static String tag = 'RealVideo';
  final String peerId;
  final String selfId;
  final bool usedatachannel;

  RealAudioJpgVideo({required this.selfId, required this.peerId, required this.usedatachannel});

  @override
  _RealAudioJpgVideoState createState() => _RealAudioJpgVideoState();
}

class JpgPainter extends CustomPainter {
  UI.Image _image;
  JpgPainter(this._image) {
    ;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // canvas.drawImage(image1, UI.Offset(60.0, 60.0), Paint());
    //canvas.drawColor(Colors.redAccent, BlendMode.src);

    if (_image != null) {
      // canvas.drawImage(_image, UI.Offset(0.0, 0.0), Paint());
      double dest_height = (size.width * _image.height) / _image.width;
      canvas.drawImageRect(
        _image,
        Rect.fromLTRB(0, 0, _image.width * 1.0, _image.height * 1.0),
        Rect.fromLTWH(0, 0, size.width, dest_height),
        Paint(),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class _RealAudioJpgVideoState extends State<RealAudioJpgVideo> {
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
  late Uint8List _imageData;
  late UI.Image _image;
  bool _recording = false;
  BytesBuilder? _bufferlist;
  int _jpg_len = 0;
  RTCDataChannel? _dataChannel;
  Session? _session;
  Timer? _timer;
  var _recvMsgEvent;

  // ignore: unused_element
  _RealAudioJpgVideoState();

  @override
  initState() {
    super.initState();
    _bufferlist = new BytesBuilder(copy: false);
    _selfId = widget.selfId;
    _peerId = widget.peerId;
    _usedatachannel = widget.usedatachannel;
    _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
      _signaling?.onMessage(event.msg);
    });

    initRenderers();
    _initWebrtc();
  }

  /*
    注：初始化显示控件
  */
  initRenderers() async {
    await _remoteRenderer.initialize();
  }

  _getImage(Uint8List imageData) async {
    UI.Codec codec = await UI.instantiateImageCodec(imageData);
    UI.FrameInfo frameInfo = await codec.getNextFrame();
    UI.Image image = frameInfo.image;
    setState(() {
      _image = image;
      if (_showremotevideo == false) {
        _showremotevideo = true;
      }
    });
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
    _signaling ??= Signaling(widget.selfId, widget.peerId, false, false);
    _signaling?.onSendSignalMessge = (String eventName, dynamic data) {
      eventBus.emit(SendMsgEvent(eventName, data));
    };
    /*
       注：信令发送"__connect",返回设备状态后回调，这个时候可以跟句客户端状态发送 offer
     */
    _signaling?.onSessionCreate = (String sessionId, String peerId, OnlineState state) {
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
          if (_usedatachannel) {
            //  _timer = Timer.periodic(Duration(seconds: 1), _handleDataChannelTest);
          }

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

        print('onLocalStream getAudioTracks track ++++++++++++++++++++++++++: ${track.enabled}');
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
    _signaling?.onSessionRTCConnectState = (Session session, RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected && _session == session) {
        print('onSessionRTCConnectState -----------: $state');
        setState(() {});
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
    _signaling?.onDataChannelState = (Session session, RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        setState(() {
          print('RTCDataChannelOpen--------------------------------_dataChannelOpened---->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
          _dataChannelOpened = true;
        });
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        setState(() {
          _dataChannelOpened = false;
        });
      }
    };
    /*
      注 接收到通过DataChannel 发送过来的消息
    */
    _signaling?.onDataChannelMessage = (Session session, dc, RTCDataChannelMessage data) {
      if (data.isBinary) {
        _bufferlist?.add(data.binary);
        int buf_list_len = _bufferlist!.length;
        if (buf_list_len > 16) {
          //  print('Got jpg data  [' + buf_list_len.toString() + ']');
          ByteBuffer buffer = _bufferlist!.toBytes().buffer;
          ByteData blob = new ByteData.view(buffer);
          int head = blob.getUint32(0, Endian.little);
          //   print('Got jpg data head $head ');
          if (blob.getUint32(0, Endian.little) == 0x04034b50) {
            int jpglen = blob.getInt16(10, Endian.little);
            int jpgwidth = blob.getInt16(6, Endian.little);
            int jpgheight = blob.getInt16(8, Endian.little);
            //  print('Got jpg data jpglen=  $jpglen  jpgwidth= $jpgwidth jpgheight= $jpgheight');
            if (buf_list_len >= jpglen + 16) {
              Uint8List dbuf = _bufferlist!.takeBytes();
              Uint8List jpgbuf = dbuf.sublist(16, jpglen);
              if (buf_list_len > jpglen + 16) {
                int llen = buf_list_len - (jpglen + 16);
                Uint8List lbuf = dbuf.sublist(jpglen + 16);
                _bufferlist?.add(lbuf);
              }
              _getImage(jpgbuf);
            }
          } else {
            _bufferlist?.clear();
          }
        }
      } else {
        print('Got text [' + data.text + ']');
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

  /*
     函数 ： 发起呼叫  
     注：  生成一个会话并创建 RTCPeerConnection 并发起Offer
  */
  _invitePeer(String sessionId, String peerId) async {
    if (peerId != _selfId) {
      _signaling?.invite(sessionId, peerId, true, false, true, false, true, "live", "MainStream", "admin", "123456");
    }
  }

  _callPeer(String sessionId, String peerId) async {
    if (peerId != _selfId) {
      _signaling?.startcall(sessionId, peerId, true, false, true, false, true, "live", "MainStream", "admin", "123456");
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
   函数： 测试使用DataChannel 发送消息
   注： 可以根据自己情况删除 Timer
*/
  _handleDataChannelTest(Timer timer) async {
    if (_dataChannelOpened) {
      String text = 'Say hello ' + timer.tick.toString() + ' times, from [$_selfId]';
      // print(' _handleDataChannelTest --------------------------------------------$text');
      _dataChannel?.send(RTCDataChannelMessage.fromBinary(Uint8List(12)));
      _dataChannel?.send(RTCDataChannelMessage(text));
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

  Widget _ImageWrapper() {
    if (_imageData == null) {
      return CircularProgressIndicator();
    }
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        image: new DecorationImage(fit: BoxFit.cover, image: MemoryImage(_imageData, scale: 0.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Real Video' + (_selfId != null ? ' [Your ID ($_selfId)] ' : '')),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                String tselfId = '$_selfId';
                String tpeerId = '$_peerId';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) {
                      return CameraSetting(selfId: tselfId, peerId: tpeerId);
                    },
                  ),
                );
              },
              tooltip: 'setup',
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SizedBox(
          width: 300.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
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
                onPressed: _muteMic,
                heroTag: 'muteMic',
              ),
              FloatingActionButton(
                child: const Icon(Icons.photo_camera),
                onPressed: _handlcapture,
                heroTag: 'capture',
                backgroundColor: _inCalling ? Colors.blue : Colors.grey,
              ),
            ],
          ),
        ),
        body: OrientationBuilder(
          builder: (context, orientation) {
            return Container(
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    top: 0.0,
                    height: MediaQuery.of(context).size.width * 240 / 320,
                    child: _showremotevideo
                        ? new CustomPaint(size: new Size(double.infinity, double.infinity), painter: new JpgPainter(_image))
                        : Container(
                            decoration: new BoxDecoration(color: Colors.black),
                            width: double.infinity,
                            child: AspectRatio(
                              aspectRatio: 320 / 240,
                              child: Center(child: new CircularProgressIndicator(backgroundColor: Color(0xffff0000))),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      onWillPop: () {
        //监听到退出按键
        _hangUp();
        return Future<bool>.value(true);
      },
    );
  }
}
