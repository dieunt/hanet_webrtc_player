import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hanet_webrtc_player/hanet_webrtc_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanet WebRTC Player Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hanet WebRTC Player Demo'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 450,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: HanetWebRTCPlayer(
                peerId: 'HANT-00-6152-98ZP-00002256',
                showFullscreen: true,
                showCapture: true,
                showRecord: true,
                showMic: true,
                showVolume: true,
                source: 'SubStream',
                showControls: true,
                onOffline: () {
                  debugPrint('onOffline');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
