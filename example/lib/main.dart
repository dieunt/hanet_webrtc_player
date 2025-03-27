import 'package:flutter/material.dart';
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
              child: const HanetWebRTCPlayer(
                peerId: 'HANT-00-92HY-VZ65-00002733',
                showFullscreen: false,
                showCapture: false,
                showRecord: false,
                showMic: true,
                showVolume: true,
                source: 'MainStream',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
