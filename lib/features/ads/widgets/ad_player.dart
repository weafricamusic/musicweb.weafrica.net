import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class AdPlayer extends StatefulWidget {
  const AdPlayer({
    super.key,
    required this.ad,
    required this.onComplete,
    required this.onSkip,
    this.durationSeconds = 5,
  });

  final Map<String, dynamic> ad;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final int durationSeconds;

  @override
  State<AdPlayer> createState() => _AdPlayerState();
}

class _AdPlayerState extends State<AdPlayer> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasCompleted = false;

  bool get _isSkippable {
    final raw = widget.ad['is_skippable'] ?? widget.ad['isSkippable'];
    if (raw is bool) return raw;
    return raw?.toString().trim().toLowerCase() == 'true';
  }

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final videoUrl = widget.ad['video_url'] as String?;
    
    if (videoUrl != null && videoUrl.isNotEmpty) {
      // Video ad
      try {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        await _controller!.initialize();
        _controller!.addListener(_onVideoProgress);
        _controller!.play();
        if (mounted) {
          setState(() => _isLoading = false);
        }
        
        // Auto-complete after duration
        Future.delayed(Duration(seconds: widget.durationSeconds), () {
          if (!_hasCompleted && mounted) {
            _completeAd();
          }
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error loading video: $e');
        }
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      // No video URL - show card UI
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onVideoProgress() {
    if (_hasCompleted || _controller == null) return;
    
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    
    // Auto-complete when video ends
    if (duration.inSeconds > 0 && position.inSeconds >= duration.inSeconds) {
      _completeAd();
    }
  }

  Future<void> _completeAd() async {
    if (_hasCompleted) return;
    if (mounted) {
      setState(() => _hasCompleted = true);
    } else {
      _hasCompleted = true;
    }
    widget.onComplete();
  }

  void _skipAd() {
    if (_hasCompleted) return;
    _controller?.pause();
    _completeAd();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // Show video if available
    if (_controller != null && _controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: (_isSkippable)
                  ? ElevatedButton(
                      onPressed: _skipAd,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Skip Ad'),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    // Fallback: show card UI
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              widget.ad['title'] ?? 'Break Time',
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Thanks for supporting!',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
