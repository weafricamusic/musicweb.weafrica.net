import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_service/audio_service.dart';

import '../playback_controller.dart';
import '../queue_sheet.dart';

/// WeAfrica Music Full Player Screen
/// 
/// Features:
/// - Playlist/source title at top
/// - Large album cover
/// - Short lyric line / caption
/// - Song title + artist with country flag
/// - Add to playlist button
/// - Progress bar with time
/// - Shuffle / Previous / Play / Next / Repeat controls
/// - Device, Share, Queue icons
/// - Lyrics preview panel
/// - "Support Artist" / "Send Coins" button
/// - Video switch button (if song has video)
/// - WeAfrica green/gold branding
class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  double? _scrubValue;
  bool _isScrubbing = false;
  final bool _showLyrics = false;

  // Country code to flag emoji mapping
  String _getCountryFlag(String? countryCode) {
    if (countryCode == null || countryCode.length != 2) return '';
    final code = countryCode.toUpperCase();
    // Convert country code to regional indicator symbols (flag emoji)
    final flag = code.codeUnits
        .map((e) => String.fromCharCode(e + 0x1F1A5))
        .join();
    return flag;
  }

  String _getCountryName(String? countryCode) {
    final Map<String, String> countries = {
      'MW': 'Malawi',
      'ZA': 'South Africa',
      'NG': 'Nigeria',
      'GH': 'Ghana',
      'KE': 'Kenya',
      'TZ': 'Tanzania',
      'UG': 'Uganda',
      'ZM': 'Zambia',
      'ZW': 'Zimbabwe',
      'BW': 'Botswana',
      'NA': 'Namibia',
      'MZ': 'Mozambique',
      'RW': 'Rwanda',
      'ET': 'Ethiopia',
      'CD': 'DRC',
      'AO': 'Angola',
    };
    if (countryCode == null) return '';
    return countries[countryCode.toUpperCase()] ?? countryCode.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0A), // Deep green-black
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final track = controller.current;
          final isPlaying = controller.isPlaying;
          final isLoading = controller.isLoading;
          final error = controller.errorMessage;

          if (track == null) {
            return _buildEmptyState();
          }

          final progress = controller.progress.clamp(0.0, 1.0);
          final sliderValue = _isScrubbing ? (_scrubValue ?? progress) : progress;
          final previewPosition = Duration(
            milliseconds: (controller.duration.inMilliseconds * sliderValue).round(),
          );

          return SafeArea(
            child: Column(
              children: [
                // App Bar
                _buildAppBar(controller),
                
                // Main content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      const SizedBox(height: 20),
                      
                      // Large Album Cover
                      _buildAlbumArt(track),
                      
                      const SizedBox(height: 32),
                      
                      // Lyric line / Caption
                      _buildLyricPreview(track),
                      
                      const SizedBox(height: 24),
                      
                      // Song Title + Artist with Country
                      _buildTrackInfo(track),
                      
                      const SizedBox(height: 8),
                      
                      // Support Artist Button
                      _buildSupportArtistButton(track),
                      
                      const SizedBox(height: 24),
                      
                      // Progress Bar
                      _buildProgressBar(
                        controller,
                        sliderValue,
                        previewPosition,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Playback Controls
                      _buildPlaybackControls(controller, isPlaying, isLoading),
                      
                      const SizedBox(height: 24),
                      
                      // Secondary Actions (Device, Share, Queue, Video)
                      _buildSecondaryActions(track, controller),
                      
                      const SizedBox(height: 32),
                      
                      // Lyrics Panel (expandable)
                      _buildLyricsPanel(track),
                      
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBar(PlaybackController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 28),
            color: Colors.white70,
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'PLAYING FROM',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your Library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              // TODO: Show more options
            },
            icon: const Icon(Icons.more_vert),
            color: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(Track track) {
    return Hero(
      tag: 'player_artwork',
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2F1A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: track.artworkUri != null
              ? CachedNetworkImage(
                  imageUrl: track.artworkUri.toString(),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const _AlbumPlaceholder(),
                  errorWidget: (context, url, error) => const _AlbumPlaceholder(),
                )
              : const _AlbumPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildLyricPreview(Track track) {
    // TODO: Fetch actual lyrics from track
    final hasLyrics = false; // track.lyrics != null;
    
    if (!hasLyrics) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2F1A).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Feel the rhythm of Africa',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            fontSize: 14,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2F1A).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Lyrics preview line...', // track.lyrics?.firstLine ?? ''
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTrackInfo(Track track) {
    final flag = _getCountryFlag(track.country);
    final countryName = _getCountryName(track.country);

    return Column(
      children: [
        // Song Title
        Text(
          track.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        // Artist with Country Flag
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (flag.isNotEmpty) ...[
              Text(
                flag,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                '${track.artist}${countryName.isNotEmpty ? ' • $countryName' : ''}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupportArtistButton(Track track) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: Show support/send coins dialog
            _showSupportDialog(track);
          },
          borderRadius: BorderRadius.circular(25),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFD4AF37), // Gold
                  Color(0xFFE5C158), // Light gold
                ],
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.favorite,
                  color: Color(0xFF1A2F1A),
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Support Artist',
                  style: TextStyle(
                    color: Color(0xFF1A2F1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F1A).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.monetization_on,
                        color: Color(0xFF1A2F1A),
                        size: 12,
                      ),
                      SizedBox(width: 2),
                      Text(
                        'Send Coins',
                        style: TextStyle(
                          color: Color(0xFF1A2F1A),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSupportDialog(Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Support Artist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Send coins to ${track.artist}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _buildCoinOption(10),
                const SizedBox(height: 12),
                _buildCoinOption(50),
                const SizedBox(height: 12),
                _buildCoinOption(100),
                const SizedBox(height: 12),
                _buildCoinOption(500),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoinOption(int amount) {
    return InkWell(
      onTap: () {
        // TODO: Process coin send
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent $amount coins!')),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.monetization_on,
              color: const Color(0xFFD4AF37),
              size: 28,
            ),
            const SizedBox(width: 16),
            Text(
              '$amount Coins',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Send',
                style: TextStyle(
                  color: const Color(0xFF1A2F1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(
    PlaybackController controller,
    double sliderValue,
    Duration previewPosition,
  ) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: const Color(0xFFD4AF37), // Gold
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbColor: const Color(0xFFD4AF37),
            overlayColor: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
          child: Slider(
            value: sliderValue.clamp(0.0, 1.0),
            onChangeStart: (_) {
              setState(() {
                _isScrubbing = true;
                _scrubValue = sliderValue;
              });
            },
            onChanged: (v) {
              setState(() => _scrubValue = v.clamp(0.0, 1.0));
            },
            onChangeEnd: (v) {
              final p = Duration(
                milliseconds: (controller.duration.inMilliseconds * v).round(),
              );
              controller.seek(p);
              setState(() {
                _isScrubbing = false;
                _scrubValue = null;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                PlaybackController.format(
                  _isScrubbing ? previewPosition : controller.position,
                ),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                PlaybackController.format(controller.duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(
    PlaybackController controller,
    bool isPlaying,
    bool isLoading,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle
        IconButton(
          onPressed: controller.toggleShuffle,
          tooltip: 'Shuffle',
          icon: Icon(
            Icons.shuffle,
            color: controller.shuffleEnabled
                ? const Color(0xFFD4AF37)
                : Colors.white.withValues(alpha: 0.2),
            size: 24,
          ),
        ),
        // Previous
        IconButton(
          onPressed: controller.canSkipPrevious
              ? controller.skipPrevious
              : null,
          onLongPress: () => controller.seekBy(const Duration(seconds: -10)),
          tooltip: 'Previous',
          icon: Icon(
            Icons.skip_previous,
            color: controller.canSkipPrevious
                ? Colors.white
                : Colors.white.withValues(alpha: 0.2),
            size: 36,
          ),
        ),
        // Play/Pause
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFD4AF37), // Gold
                Color(0xFFE5C158), // Light gold
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: IconButton(
            onPressed: isLoading ? null : controller.togglePlay,
            tooltip: isLoading
                ? 'Loading'
                : (isPlaying ? 'Pause' : 'Play'),
            icon: isLoading
                ? const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1A2F1A)),
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: const Color(0xFF1A2F1A),
                    size: 40,
                  ),
          ),
        ),
        // Next
        IconButton(
          onPressed: controller.canSkipNext
              ? controller.skipNext
              : null,
          onLongPress: () => controller.seekBy(const Duration(seconds: 10)),
          tooltip: 'Next',
          icon: Icon(
            Icons.skip_next,
            color: controller.canSkipNext
                ? Colors.white
                : Colors.white.withValues(alpha: 0.2),
            size: 36,
          ),
        ),
        // Repeat
        IconButton(
          onPressed: controller.toggleRepeat,
          tooltip: 'Repeat',
          icon: Icon(
            controller.repeatMode == AudioServiceRepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: controller.repeatEnabled
                ? const Color(0xFFD4AF37)
                : Colors.white.withValues(alpha: 0.2),
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryActions(Track track, PlaybackController controller) {
    final hasVideo = false; // TODO: Check if track has video
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Device/Output
        _buildActionButton(
          icon: Icons.speaker_outlined,
          label: 'Device',
          onTap: () {
            // TODO: Show device selection
          },
        ),
        // Share
        _buildActionButton(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: controller.shareCurrent,
        ),
        // Queue
        _buildActionButton(
          icon: Icons.queue_music_outlined,
          label: 'Queue',
          onTap: () => showQueueSheet(context),
        ),
        // Video (if available)
        if (hasVideo)
          _buildActionButton(
            icon: Icons.videocam_outlined,
            label: 'Video',
            onTap: () {
              // TODO: Switch to video mode
            },
            isActive: true,
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFD4AF37).withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? const Color(0xFFD4AF37)
                  : Colors.white.withValues(alpha: 0.2),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFFD4AF37)
                    : Colors.white.withValues(alpha: 0.2),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsPanel(Track track) {
    // TODO: Check if track has lyrics
    final hasLyrics = false; // track.lyrics != null && track.lyrics!.isNotEmpty;
    
    if (!hasLyrics) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2F1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        collapsedIconColor: Colors.white70,
        iconColor: const Color(0xFFD4AF37),
        title: const Row(
          children: [
            Icon(
              Icons.lyrics_outlined,
              color: Color(0xFFD4AF37),
              size: 20,
            ),
            SizedBox(width: 12),
            Text(
              'Lyrics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Lyrics would appear here...\n(Scrollable lyrics panel)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note,
            size: 80,
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Nothing playing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a track to start listening',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: const Color(0xFF1A2F1A),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text(
              'Browse Music',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.album,
            size: 80,
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'WEAFRICA',
            style: TextStyle(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}