
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Platform;
class LocalPlayer extends StatefulWidget {
  final String apppath;
  final String peerId;
   LocalPlayer({required this.apppath,required this.peerId});


  @override
   _LocalPlayerState createState() => _LocalPlayerState();
}

class _LocalPlayerState extends  State<LocalPlayer>  {
 
   VideoPlayerController ?_controller;
  double _value = 0;
  bool _initplayered = false;
  bool _closeed = false;
  @override
  initState() {
    super.initState();
       var path = widget.apppath;
   var file = File("$path/test.mp4");
    _controller = VideoPlayerController.file(file);

    _controller!.addListener(videoPlayerControllerCallBack);
  
    _controller!.setLooping(false);
    _controller!.initialize().then((_) => setState(() {_initplayered = true;}));
    _controller!.play();
  }
  videoPlayerControllerCallBack() {
     int pseconds = _controller!.value.position.inSeconds;
       int dseconds = _controller!.value.duration.inSeconds;
       if(!_closeed){
      setState(() {
        if(dseconds>0){
               _value = pseconds/dseconds;
        }
      
       
      });
       }
  }
    Future<void> _releaseRemotePlayer() async {
        await  _controller!.pause();
          _controller!.removeListener(videoPlayerControllerCallBack);
          

  }
  Future<String> _getAppDocPath() async {
    var appDocDir = await getApplicationDocumentsDirectory();
    String appDocPath = appDocDir!.path;
    return appDocPath;
  }

   @override
  Widget build(BuildContext context) {
     return  WillPopScope(
    child: Scaffold(
        appBar: AppBar(
          title: Text('local player'),
          
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
                        margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        decoration: BoxDecoration(color: Colors.black),
                        child: _initplayered && _controller!.value.isInitialized
                              ?AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: VideoPlayer(_controller!),
                            )
                            :Container(decoration: new BoxDecoration(color: Colors.black),
                                  height: 200.0,
                                  width: double.infinity,
                                  child: Center(
                                          child: new CircularProgressIndicator(
                                            backgroundColor: Color(0xffff0000),
                                           ),
                                  )

                              ),
                        
                      )),
                  Positioned(
                      left: 0.0,
                      right: 0.0,
                      top: 200.0,
                      height: 5.0,
                      child: LinearProgressIndicator(
                        value: _value,
                        backgroundColor: Colors.cyan[100],
                        valueColor: new AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                     ),
                    
                ]),
              );
            }),
    
         floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              if(_controller!=null){
              _controller!.value.isPlaying
                  ? _controller!.pause()
                  : _controller!.play();
            }
            });
          },
          child: Icon(        
            (_initplayered &&_controller!.value.isPlaying) ? Icons.pause : Icons.play_arrow,      
          ),
        ),
       

    ),
       onWillPop: (){
       //监听到退出按键
        _closeed = true;
       _releaseRemotePlayer();
        return Future<bool>.value(true);
      },
    );
  }


  @override
  void dispose() {
      _closeed = true;
     super.dispose();
    _controller!.dispose();
   
  
  }
}