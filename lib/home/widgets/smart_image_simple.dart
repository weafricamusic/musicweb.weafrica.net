import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// SIMPLE VERSION: SmartImage that just works
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
      return _buildPlaceholder();
    }
    
    final url = _getImageUrl(imagePath!);
    
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) {
            debugPrint('❌ SmartImage Error for: $url');
            debugPrint('   Error: $error');
            return _buildError();
          },
        ),
      ),
    );
  }
  
  /// SIMPLE URL generation that we know works
  String _getImageUrl(String path) {
    // If it's already a full URL, use it
    if (path.startsWith('http')) {
      return path;
    }
    
    // Clean the path
    var cleanPath = path.trim();
    if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    
    // Use the URL format we KNOW works from our tests
    const baseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
    
    // Canonical public bucket name uses hyphen: song-thumbnails.

    // Bare filename (no folders) is typically in the public hyphen bucket.
    if (!cleanPath.contains('/')) {
      return '$baseUrl/storage/v1/object/public/song-thumbnails/${Uri.encodeComponent(cleanPath)}';
    }
    
    // Nested path: use the public bucket.
    return '$baseUrl/storage/v1/object/public/song-thumbnails/$cleanPath';
  }
  
  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF2A2A2A),
        ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Color(0xFF1DB954),
          size: 40,
        ),
      ),
    );
  }
  
  Widget _buildError() {
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
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image,
              color: Color(0xFF1DB954),
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              'No Image',
              style: TextStyle(
                color: Color(0xFF1DB954),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
