// ignore_for_file: prefer_typing_uninitialized_variables

import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:core';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'signaling.dart';
import 'event_bus_util.dart';
import 'event_message.dart';

class CameraSetting extends StatefulWidget {
  static String tag = 'call_sample';
  final String peerId;
  final String selfId;
  CameraSetting({required this.selfId,required this.peerId});

  @override
  _CameraSettingState createState() => _CameraSettingState();
}

class _CameraSettingState extends State<CameraSetting> {

  String? _selfId;
  String? _peerId;
  String? _sessionid;


  var _recvMsgEvent;
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  // ignore: unused_element
  _CameraSettingState();

  @override
  initState() {
    super.initState();
     
     
       _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
        // print('CallSample recive ReciveMsgEvent --> ${event.msg}');  
              onMessage(event.msg);   
              
       });

   
  }

  @override
  deactivate() {
    super.deactivate();
    eventBus.off(_recvMsgEvent);

  }

    void onMessage(message) async {
    //print('onMessage recv $message');
    Map<String, dynamic> mapData=  _decoder.convert(message);  
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    switch (eventName) {
      case '_postmessage':
        { 
        }
        break;
       default:
        break;
    }
    }
  @override
  Widget build(BuildContext context) {
     return  WillPopScope(
    child: Scaffold(
        appBar: AppBar(
          title: Text('Setup' +
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
                      child: Container(
                      width: double.infinity,
                      height: 200.0,
                       child: Container(decoration: new BoxDecoration(color: Colors.blue),
                                  height: 200.0,
                                  width: double.infinity,
                                  child: Center(
                                          
                                  )

                                  ),
               
                      ),
                  )
                    
                ]),
              );
            })
       

   
    ),
       onWillPop: (){
       //监听到退出按键
   
        return Future<bool>.value(true);
      },
    );
  }
}
