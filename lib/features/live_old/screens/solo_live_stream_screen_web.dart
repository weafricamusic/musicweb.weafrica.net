import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';

class SoloLiveStreamScreen extends StatefulWidget {
  const SoloLiveStreamScreen({
    super.key,
    required this.title,
    required this.hostName,
    required this.channelId,
    this.token,
    this.liveStreamId,
  });

  final String title;
  final String hostName;
  final String channelId;
  final String? token;
  final String? liveStreamId;

  @override
  State<SoloLiveStreamScreen> createState() => _SoloLiveStreamScreenState();
}

class _SoloLiveStreamScreenState extends State<SoloLiveStreamScreen> {
  html.VideoElement? _localVideo;
  dynamic _client;

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  Future<void> _initAgora() async {
    try {
      // Wait for AgoraRTC to load properly on web (fix race condition)
      dynamic agoraRtc;
      int attempts = 0;
      
      while (agoraRtc == null && attempts < 50) {
        agoraRtc = js.context['AgoraRTC'];
        if (agoraRtc == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
      }
      
      if (agoraRtc == null) {
        throw Exception('AgoraRTC failed to load after 5 seconds');
      }

      // Create client
      _client = agoraRtc.callMethod('createClient', [
        js.JsObject.jsify({
          'mode': 'live',
          'codec': 'vp8',
        })
      ]);

      // Set client role
      _client.callMethod('setClientRole', ['host']);

      // Join channel
      await _client.callMethod('join', [
        null, // appId (from token)
        widget.channelId,
        widget.token,
        null  // uid
      ]).toFuture();

      // Create local track
      final localTrack = await agoraRtc.callMethod('createCameraVideoTrack').toFuture();
      
      // Publish
      await _client.callMethod('publish', [localTrack]).toFuture();
      
      // Play local video
      _localVideo = html.VideoElement();
      localTrack.callMethod('play', [_localVideo]);
    } catch (e) {
      print('Error initializing Agora: $e');
    }
  }

  @override
  void dispose() {
    if (_client != null) {
      try {
        _client.callMethod('leave');
      } catch (e) {
        // Ignore leave errors during dispose
        print('Error leaving channel during dispose: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (full screen)
          Container(color: Colors.black),
          
          // Local video (small preview)
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              width: 120,
              height: 180,
              color: Colors.grey[900],
              child: const Center(
                child: Text('Camera Preview', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
          
          // Controls
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('END LIVE', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
          
          // Live indicator
          Positioned(
            top: 60,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                  SizedBox(width: 6),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
