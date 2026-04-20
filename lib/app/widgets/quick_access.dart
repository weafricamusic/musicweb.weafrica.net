import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/supabase_media_url.dart';
import '../theme.dart';
import 'auto_artwork.dart';

@immutable
class QuickAccessItem {
  const QuickAccessItem({
    required this.title,
    required this.onTap,
    this.imageUri,
  });

  final String title;
  final Uri? imageUri;
  final VoidCallback onTap;
}

class QuickAccessCard extends StatelessWidget {
  const QuickAccessCard({
    super.key,
    required this.title,
    required this.onTap,
    this.imageUri,
  });

  final String title;
  final Uri? imageUri;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final safeTitle = title.trim().isEmpty ? 'Recent' : title.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.surface2,
                AppColors.brandOrange.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 56.0;
              final imageSize = (h - 16.0).clamp(36.0, 44.0);

              return Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: imageSize,
                        height: imageSize,
                        child: _ArtworkThumb(imageUri: imageUri, seed: safeTitle),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        safeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({
    super.key,
    required this.items,
    this.maxItems = 8,
    this.crossAxisCount = 2,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.mainAxisExtent = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<QuickAccessItem> items;
  final int maxItems;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double mainAxisExtent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final count = math.min(items.length, maxItems);

    if (count == 0) {
      return Padding(
        padding: padding,
        child: Text(
          'Nothing here yet',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return GridView.builder(
      padding: padding,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisExtent: mainAxisExtent,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return QuickAccessCard(
          title: item.title,
          imageUri: item.imageUri,
          onTap: item.onTap,
        );
      },
    );
  }
}

class _ArtworkThumb extends StatelessWidget {
  const _ArtworkThumb({required this.imageUri, required this.seed});

  final Uri? imageUri;
  final String seed;

  @override
  Widget build(BuildContext context) {
    return _ArtworkThumbWithFallbacks(imageUri: imageUri, seed: seed);
  }
}

class _ArtworkThumbWithFallbacks extends StatefulWidget {
  const _ArtworkThumbWithFallbacks({required this.imageUri, required this.seed});

  final Uri? imageUri;
  final String seed;

  @override
  State<_ArtworkThumbWithFallbacks> createState() => _ArtworkThumbWithFallbacksState();
}

class _ArtworkThumbWithFallbacksState extends State<_ArtworkThumbWithFallbacks> {
  static final Set<String> _knownBadOriginalUrls = <String>{};

  late List<String> _urls;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _urls = _buildCandidates(widget.imageUri);
  }

  @override
  void didUpdateWidget(covariant _ArtworkThumbWithFallbacks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUri?.toString() != widget.imageUri?.toString()) {
      _urls = _buildCandidates(widget.imageUri);
      _index = 0;
    }
  }

  static List<String> _buildCandidates(Uri? uri) {
    final raw = uri?.toString().trim() ?? '';
    if (raw.isEmpty) return const [];
    if (_knownBadOriginalUrls.contains(raw)) return const [];

    final out = <String>[];
    void add(String v) {
      final s = v.trim();
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    String fixSpacesBeforeExtension(String input) {
      // Fix keys like "Gwamba%20Saint%20.jpg" (space before extension)
      // and "Gwamba Saint .jpg".
      return input.replaceAllMapped(
        RegExp(r'(?:%20|\s)+(\.(?:jpe?g|png|webp|gif))(\?|$)', caseSensitive: false),
        (m) => '${m[1]}${m[2]}',
      );
    }

    void addBucketAliases(String url) {
      final parsed = Uri.tryParse(url);
      final normalized = parsed == null
          ? url
          : (SupabaseMediaUrl.normalize(parsed)?.toString() ?? url);

      // Prefer normalized (hyphen) first.
      add(normalized);

      // Keep original as fallback only if different.
      if (normalized != url) add(url);
    }

    void addExtensionFallbacks(String url) {
      addBucketAliases(url);

      // Common drift: some rows point at .webp but the bucket has .jpg/.jpeg.
      final swappedJpg = url.replaceAllMapped(
        RegExp(r'\.webp(\?|$)', caseSensitive: false),
        (m) => '.jpg${m[1]}',
      );
      if (swappedJpg != url) addBucketAliases(swappedJpg);

      final swappedJpeg = url.replaceAllMapped(
        RegExp(r'\.webp(\?|$)', caseSensitive: false),
        (m) => '.jpeg${m[1]}',
      );
      if (swappedJpeg != url) addBucketAliases(swappedJpeg);
    }

    // 1) Original
    addExtensionFallbacks(raw);

    // 2) Sanitized (remove stray space before extension)
    final fixed = fixSpacesBeforeExtension(raw);
    if (fixed != raw) {
      addExtensionFallbacks(fixed);
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty) {
      return AutoArtwork(seed: widget.seed, icon: Icons.music_note, showInitials: false);
    }

    final imageUrl = _urls[_index];

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => AutoArtwork(
        seed: widget.seed,
        icon: Icons.music_note,
        showInitials: false,
      ),
      errorWidget: (context, url, error) {
        if (_index < _urls.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _index++);
          });

          return AutoArtwork(
            seed: widget.seed,
            icon: Icons.music_note,
            showInitials: false,
          );
        }

        // Final failure for this artwork: avoid repeating retries/logs on rebuild.
        final original = widget.imageUri?.toString().trim();
        final didMarkBad = (original != null && original.isNotEmpty)
            ? _knownBadOriginalUrls.add(original)
            : false;

        // CachedNetworkImage can rebuild it errorWidget multiple times; only log once.
        if (kDebugMode && (didMarkBad || original == null || original.isEmpty)) {
          debugPrint('QuickAccessCard image failed: $error');
        }
        return AutoArtwork(seed: widget.seed, icon: Icons.broken_image, showInitials: false);
      },
    );
  }
}
