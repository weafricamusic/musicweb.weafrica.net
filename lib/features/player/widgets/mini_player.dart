import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../app/theme.dart';
import '../playback_controller.dart';

/// WeAfrica Music Mini Player
/// 
/// Features:
/// - Small cover image
/// - Song title & artist name
/// - Device/output icon
/// - Add to playlist button
/// - Play/Pause button
/// - WeAfrica green/gold branding
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.onTap,
    this.showProgressBar = true,
  });

  final VoidCallback onTap;
  final bool showProgressBar;

  static const double _height = 64;
  static const double _artworkSize = 48;

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.current;
        final isPlaying = controller.isPlaying;
        final isLoading = controller.isLoading;

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: track == null ? null : onTap,
            child: Container(
              height: _height,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A2F1A), // WeAfrica dark green
                    Color(0xFF0F1F0F), // Darker green
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.3), // Gold border
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar (thin line at top)
                  if (showProgressBar) ...[
                    _buildProgressBar(controller),
                  ],
                  // Main content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          // Artwork with Hero
                          _buildArtwork(track),
                          const SizedBox(width: 12),
                          // Title & Artist
                          Expanded(
                            child: _buildTrackInfo(track),
                          ),
                          // Action buttons
                          _buildDeviceButton(),
                          _buildAddButton(track),
                          _buildPlayButton(track, isPlaying, isLoading),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(PlaybackController controller) {
    final progress = controller.progress.clamp(0.0, 1.0);
    
    return Container(
      height: 2,
      margin: const EdgeInsets.only(top: 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.transparent,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)), // Gold
        ),
      ),
    );
  }

  Widget _buildArtwork(Track? track) {
    return Hero(
      tag: 'player_artwork',
      child: Container(
        height: _artworkSize,
        width: _artworkSize,
        decoration: BoxDecoration(
          color: const Color(0xFF2A3F2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: track?.artworkUri != null
            ? CachedNetworkImage(
                imageUrl: track!.artworkUri.toString(),
                fit: BoxFit.cover,
                placeholder: (context, url) => const _MusicIcon(),
                errorWidget: (context, url, error) => const _MusicIcon(),
              )
            : const _MusicIcon(),
      ),
    );
  }

  Widget _buildTrackInfo(Track? track) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Song Title
        Text(
          track?.title ?? 'Nothing playing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        // Artist Name
        Text(
          track?.artist ?? 'Select a track',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceButton() {
    return IconButton(
      onPressed: () {
        // TODO: Show device/output selection
      },
      tooltip: 'Output Device',
      icon: Icon(
        Icons.speaker_outlined,
        color: const Color(0xFFD4AF37).withValues(alpha: 0.8),
        size: 20,
      ),
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildAddButton(Track? track) {
    return IconButton(
      onPressed: track == null
          ? null
          : () {
              // TODO: Show add to playlist menu
            },
      tooltip: 'Add to Playlist',
      icon: Icon(
        Icons.add_circle_outline,
        color: track == null
            ? Colors.white.withValues(alpha: 0.3)
            : const Color(0xFFD4AF37).withValues(alpha: 0.9),
        size: 22,
      ),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildPlayButton(Track? track, bool isPlaying, bool isLoading) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      child: Material(
        color: const Color(0xFFD4AF37), // Gold background
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: track == null ? null : () => PlaybackController.instance.togglePlay(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1A2F1A)),
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: const Color(0xFF1A2F1A), // Dark green icon
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MusicIcon extends StatelessWidget {
  const _MusicIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.music_note,
        color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
        size: 24,
      ),
    );
  }
}