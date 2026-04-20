import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/song_model.dart';

class MusicCard extends StatelessWidget {
  const MusicCard({
    super.key,
    required this.song,
    required this.onTap,
  });

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Debug logging to see what's happening
    if (kDebugMode) {
      debugPrint('🎵 MusicCard: ${song.title}');
      debugPrint('📸 thumbnail raw: ${song.thumbnail}');
      debugPrint('🔗 imageUrl computed: ${song.imageUrl}');
      debugPrint('   imageUrl is null? ${song.imageUrl == null}');
      debugPrint('   imageUrl isEmpty? ${song.imageUrl?.isEmpty ?? true}');
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // Direct image loading without SmartImage
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: kDebugMode
                        ? Border.all(color: Colors.red, width: 3)
                        : null,
                    color: Colors.grey[900], // Fallback color
                  ),
                  child: song.imageUrl != null && song.imageUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            song.imageUrl!,
                            width: 140,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('❌ Image load error for ${song.title}:');
                              debugPrint('   URL: ${song.imageUrl}');
                              debugPrint('   Error: $error');
                              return _buildErrorContainer();
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return _buildLoadingContainer(loadingProgress);
                            },
                          ),
                        )
                      : _buildNoImageContainer(),
                ),
                
                // Playing indicator
                if (song.isPlaying)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                
                // Trending indicator
                if (song.isTrending)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.whatshot,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 10),
            
            // Song title
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            
            const SizedBox(height: 2),
            
            // Artist name
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            
            // Debug info (only in debug mode)
            if (kDebugMode && (song.thumbnail ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'thumb: ${(song.thumbnail ?? '').length > 22 ? '${(song.thumbnail ?? '').substring(0, 22)}…' : (song.thumbnail ?? '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.70),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorContainer() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.red[900]?.withValues(alpha: 0.3),
      ),
      child: Center(
        child: Icon(
          Icons.broken_image,
          color: Colors.red[300],
          size: 40,
        ),
      ),
    );
  }

  Widget _buildLoadingContainer(ImageChunkEvent? loadingProgress) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[900],
      ),
      child: Center(
        child: CircularProgressIndicator(
          value: loadingProgress?.expectedTotalBytes != null
              ? loadingProgress!.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!
              : null,
          color: const Color(0xFF1DB954),
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildNoImageContainer() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            Colors.grey[900]!,
            Colors.grey[800]!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          color: Colors.grey[600],
          size: 50,
        ),
      ),
    );
  }
}