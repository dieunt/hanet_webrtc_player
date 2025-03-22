import 'package:flutter/material.dart';

/// A WebRTC video player widget that currently displays a black rectangle.
/// This widget can be extended to implement WebRTC video playback functionality.
class HanetWebRTCPlayer extends StatelessWidget {
  /// The width of the video player widget.
  final double width;

  /// The height of the video player widget.
  final double height;

  /// Creates a new instance of [HanetWebRTCPlayer].
  ///
  /// [width] and [height] are optional parameters that default to 300 and 200 respectively.
  const HanetWebRTCPlayer({super.key, this.width = 300, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.black,
      child: const Center(
        child: Text(
          'WebRTC Player',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}
