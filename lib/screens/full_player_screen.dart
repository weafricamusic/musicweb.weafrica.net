import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio.dart';
import '../services/playback_ad_gate.dart';
import '../app/utils/user_facing_error.dart';
import '../features/library/services/library_service.dart';
import '../features/player/playback_controller.dart';
import '../features/player/song_comments_sheet.dart';

class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key});

  static const Color _accent = Color(0xFF1DB954);

  Future<void> _downloadCurrentTrack(BuildContext context) async {
    final track = PlaybackController.instance.current;
    if (track == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing is playing yet.')),
      );
      return;
    }

    final res = await LibraryService().downloadTrack(track);
    if (!context.mounted) return;

    res.fold(
      onSuccess: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved for offline playback.')),
        );
      },
      onFailure: (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Download failed. Please try again.',
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = maybeWeafricaAudioHandler;
    if (handler == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Now Playing'),
        actions: [
          IconButton(
            tooltip: 'Download for offline',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => _downloadCurrentTrack(context),
          ),
          IconButton(
            tooltip: 'Comments',
            icon: const Icon(Icons.mode_comment_outlined),
            onPressed: () async {
              final track = PlaybackController.instance.current;
              final trackId = (track?.id ?? '').trim();
              if (track == null || trackId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Comments are unavailable for this track.')),
                );
                return;
              }

              await showSongCommentsSheet(context, track: track);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Subtle premium gradient.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0B0B0B),
                    Color(0xFF000000),
                  ],
                ),
              ),
            ),
          ),
          // Gentle vignette.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            builder: (context, snapshot) {
              final item = snapshot.data;
              if (item == null) return const SizedBox.shrink();

              return SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 14,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Hero(
                        // Match the mini-player Hero tag.
                        tag: 'player_artwork',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: StreamBuilder<PlayerState>(
                              stream: handler.playerStateStream,
                              builder: (context, stateSnap) {
                                final state = stateSnap.data;
                                final isBuffering = state?.processingState ==
                                    ProcessingState.buffering;

                                return Stack(
                                  fit: StackFit.expand,
                                  alignment: Alignment.center,
                                  children: [
                                    if (item.artUri == null)
                                      const ColoredBox(
                                        color: Color(0xFF111111),
                                        child: Center(
                                          child: Icon(
                                            Icons.music_note,
                                            size: 120,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    else
                                      Image.network(
                                        item.artUri.toString(),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const ColoredBox(
                                          color: Color(0xFF111111),
                                          child: Center(
                                            child: Icon(
                                              Icons.music_note,
                                              size: 120,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Subtle gradient on top of artwork.
                                    const IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x22000000),
                                              Color(0x33000000),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isBuffering)
                                      const ColoredBox(
                                        color: Color(0x55000000),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAAAAA),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  StreamBuilder<Duration>(
                    stream: handler.positionStream,
                    builder: (context, posSnap) {
                      final position = posSnap.data ?? Duration.zero;
                      final total = item.duration ?? handler.duration;
                      final totalSeconds =
                          total.inSeconds <= 0 ? 1 : total.inSeconds;
                      final valueSeconds =
                          position.inSeconds.clamp(0, totalSeconds);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 18,
                                ),
                                thumbColor: Colors.white,
                                activeTrackColor: _accent,
                                inactiveTrackColor: const Color(0xFF333333),
                                overlayColor: _accent.withValues(alpha: 0.18),
                              ),
                              child: Slider(
                                value: valueSeconds.toDouble(),
                                max: totalSeconds.toDouble(),
                                onChanged: (v) {
                                  handler.seek(Duration(seconds: v.round()));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _format(position),
                                    style: const TextStyle(
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _format(total),
                                    style: const TextStyle(
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    builder: (context, stateSnap) {
                      final playing = stateSnap.data?.playing ?? false;
                      final shuffleMode = stateSnap.data?.shuffleMode ??
                          AudioServiceShuffleMode.none;
                      final repeatMode = stateSnap.data?.repeatMode ??
                          AudioServiceRepeatMode.none;

                      final shuffleEnabled =
                          shuffleMode == AudioServiceShuffleMode.all;
                      final repeatEnabled =
                          repeatMode != AudioServiceRepeatMode.none;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    tooltip: 'Shuffle',
                                    icon: Icon(
                                      Icons.shuffle,
                                      color: shuffleEnabled ? _accent : Colors.white,
                                    ),
                                    onPressed: () {
                                      handler.setShuffleMode(
                                        shuffleEnabled
                                            ? AudioServiceShuffleMode.none
                                            : AudioServiceShuffleMode.all,
                                      );
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Repeat',
                                    icon: Icon(
                                      repeatMode == AudioServiceRepeatMode.one
                                          ? Icons.repeat_one
                                          : Icons.repeat,
                                      color: repeatEnabled ? _accent : Colors.white,
                                    ),
                                    onPressed: () {
                                      final next = switch (repeatMode) {
                                        AudioServiceRepeatMode.none =>
                                          AudioServiceRepeatMode.all,
                                        AudioServiceRepeatMode.all =>
                                          AudioServiceRepeatMode.one,
                                        AudioServiceRepeatMode.one =>
                                          AudioServiceRepeatMode.none,
                                        AudioServiceRepeatMode.group =>
                                          AudioServiceRepeatMode.none,
                                      };
                                      handler.setRepeatMode(next);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.skip_previous,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                  onPressed: handler.skipToPrevious,
                                ),
                                const SizedBox(width: 18),
                                StreamBuilder<PlayerState>(
                                  stream: handler.playerStateStream,
                                  builder: (context, psSnap) {
                                    final state = psSnap.data;
                                    final isBuffering =
                                        state?.processingState ==
                                            ProcessingState.buffering;
                                    return IconButton(
                                      icon: isBuffering
                                          ? const SizedBox(
                                              height: 44,
                                              width: 44,
                                              child:
                                                  CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              playing
                                                  ? Icons.pause_circle_filled
                                                  : Icons.play_circle_filled,
                                              size: 76,
                                              color: _accent,
                                            ),
                                      onPressed:
                                          playing ? handler.pause : handler.play,
                                    );
                                  },
                                ),
                                const SizedBox(width: 18),
                                IconButton(
                                  icon: const Icon(
                                    Icons.skip_next,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                  onPressed: handler.skipToNext,
                                ),
                              ],
                            ),
                            if (kDebugMode) ...[
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      debugPrint('🎬 MANUAL AD TRIGGER');
                                      final adInfo =
                                          await PlaybackAdGate.instance.getNextAdType();
                                      debugPrint('Ad type: ${adInfo['requiredMedia']}');

                                      final required = switch (adInfo['requiredMedia']) {
                                        'video' => InterstitialRequiredMedia.video,
                                        'audio' => InterstitialRequiredMedia.audio,
                                        _ => null,
                                      };

                                      PlaybackAdGate.instance
                                          .debugEmitInterstitialNow(requiredMedia: required);
                                    },
                                    child: const Text('TEST AD'),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
