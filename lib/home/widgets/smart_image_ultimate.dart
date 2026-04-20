import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// ULTIMATE SmartImage that handles ALL Supabase URL formats
class SmartImage extends StatelessWidget {
  final String? imagePath;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  
  const SmartImage({
    super.key,
    required this.imagePath,
    this.width = 140,
    this.height = 140,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });
  
  @override
  Widget build(BuildContext context) {
    debugPrint('🖼️ SmartImage received: "${imagePath ?? "(null)"}"');
    
    if (imagePath == null || imagePath!.isEmpty) {
      return _buildPlaceholder('No image');
    }
    
    final urls = _getPossibleUrls(imagePath!);
    debugPrint('   Generated ${urls.length} possible URLs');
    
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: _ImageWithFallbacks(
          urls: urls,
          fit: fit,
          placeholder: _buildPlaceholder('Loading...'),
          errorWidget: _buildError('Image not found'),
        ),
      ),
    );
  }
  
  /// Generate ALL possible working URLs for an image
  List<String> _getPossibleUrls(String input) {
    if (input.isEmpty) return [];
    
    final urls = <String>{};
    var path = input.trim();
    
    // If it's already a full URL, normalize legacy bucket names.
    if (path.startsWith('http')) {
      final normalized = path
          .replaceAll(
            '/storage/v1/object/public/song_thumbnails/',
            '/storage/v1/object/public/song-thumbnails/',
          )
          .replaceAll(
            '/storage/v1/object/song_thumbnails/',
            '/storage/v1/object/song-thumbnails/',
          );
      urls.add(normalized);
      if (normalized != path) urls.add(path);
    } else {
      // It's a path, generate all possible URL formats
      const baseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
      
      // Remove leading slash
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      
      // Canonical: hyphen bucket name.
      urls.add('$baseUrl/storage/v1/object/public/song-thumbnails/$path');
      urls.add('$baseUrl/storage/v1/object/song-thumbnails/$path');
      
      // Format 5: Try in different buckets
      urls.add('$baseUrl/storage/v1/object/public/thumbnails/$path');
      urls.add('$baseUrl/storage/v1/object/public/media/$path');
    }
    
    // Remove any empty URLs and return as list
    return urls.where((url) => url.isNotEmpty).toList();
  }
  
  Widget _buildPlaceholder(String text) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF111111),
            const Color(0xFF1A1A1A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_note,
              color: Color(0xFF1DB954),
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF1DB954),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildError(String message) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1DB954).withValues(alpha: 0.1),
            const Color(0xFF1ED760).withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.broken_image,
              color: Color(0xFF1DB954),
              size: 40,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget that tries multiple URLs until one works
class _ImageWithFallbacks extends StatefulWidget {
  final List<String> urls;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;
  
  const _ImageWithFallbacks({
    required this.urls,
    required this.fit,
    required this.placeholder,
    required this.errorWidget,
  });
  
  @override
  State<_ImageWithFallbacks> createState() => _ImageWithFallbacksState();
}

class _ImageWithFallbacksState extends State<_ImageWithFallbacks> {
  int _currentIndex = 0;
  
  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= widget.urls.length) {
      return widget.errorWidget;
    }
    
    final currentUrl = widget.urls[_currentIndex];
    debugPrint('   Trying URL ${_currentIndex + 1}/${widget.urls.length}: $currentUrl');
    
    return CachedNetworkImage(
      imageUrl: currentUrl,
      fit: widget.fit,
      placeholder: (context, url) => widget.placeholder,
      errorWidget: (context, url, error) {
        debugPrint('   ❌ Failed: $error');
        
        // Try next URL
        Future.microtask(() {
          if (mounted && _currentIndex < widget.urls.length - 1) {
            setState(() {
              _currentIndex++;
            });
          }
        });
        
        // Show placeholder while loading next
        return widget.placeholder;
      },
    );
  }
}
