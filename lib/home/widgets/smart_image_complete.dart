import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// COMPLETE WORKING VERSION of SmartImage
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
    if (imagePath == null || imagePath!.isEmpty) {
      debugPrint('🖼️ SmartImage: No image path provided');
      return _buildPlaceholder('No image');
    }

    final url = _getImageUrl(imagePath!);
    debugPrint('🖼️ SmartImage loading: $url');

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          placeholder: (context, url) => _buildPlaceholder('Loading...'),
          errorWidget: (context, url, error) {
            debugPrint('❌ SmartImage Failed:');
            debugPrint('   URL: $url');
            debugPrint('   Original path: $imagePath');
            debugPrint('   Error: $error');
            return _buildError('Failed to load');
          },
        ),
      ),
    );
  }

  /// Convert image path to working URL
  String _getImageUrl(String input) {
    if (input.isEmpty) return '';

    var path = input.trim();
    
    debugPrint('🖼️ SmartImage processing: $path');

    // If it's already a full URL, return it
    if (path.startsWith('http://') || path.startsWith('https://')) {
      debugPrint('   ✅ Already full URL: $path');
      return path;
    }

    const baseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';

    // Remove leading slash if present
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    // Handle different path formats
    if (path.contains('storage/v1/object/')) {
      // Already has storage path format
      if (path.startsWith('storage/')) {
        return '$baseUrl/$path';
      }
      return '$baseUrl/$path';
    }

    // If it contains bucket name in the path
    if (path.startsWith('album-covers/') || 
        path.startsWith('song-thumbnails/') || 
        path.startsWith('songs/') || 
        path.startsWith('media/') ||
        path.startsWith('uploads/')) {
      // Path already includes bucket, use public URL
      final fullUrl = '$baseUrl/storage/v1/object/public/$path';
      debugPrint('   ✅ Built URL with bucket: $fullUrl');
      return fullUrl;
    }

    // Bare filename - put in song-thumbnails bucket
    if (!path.contains('/')) {
      final fullUrl = '$baseUrl/storage/v1/object/public/song-thumbnails/${Uri.encodeComponent(path)}';
      debugPrint('   ✅ Built URL for bare filename: $fullUrl');
      return fullUrl;
    }

    // Default fallback - assume it's a path in the public bucket
    final fullUrl = '$baseUrl/storage/v1/object/public/$path';
    debugPrint('   ✅ Built URL (fallback): $fullUrl');
    return fullUrl;
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
            const Color(0xFF222222),
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