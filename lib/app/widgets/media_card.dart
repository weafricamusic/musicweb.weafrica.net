import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../theme.dart';
import 'auto_artwork.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.imageUri,
    this.size = 160,
    this.width,
    this.height,
    this.onTap,
    this.onLongPress,
    this.leadingIcon = Icons.album,
    this.badgeLabel,
    this.badgeColor,
  });

  final String title;
  final String subtitle;
  final Uri? imageUri;
  final double size;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final IconData leadingIcon;
  final String? badgeLabel;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final cardWidth = width ?? size;

    final safeTitle = title.trim().isEmpty ? 'Untitled' : title.trim();
    final safeSubtitle = subtitle.trim();
    final hasSubtitle = safeSubtitle.isNotEmpty;

    final imageUrl = imageUri?.toString().trim() ?? '';
    final hasImage = imageUrl.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: cardWidth,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: !hasImage
                          ? AutoArtwork(seed: safeTitle, icon: leadingIcon)
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => AutoArtwork(
                                seed: safeTitle,
                                icon: leadingIcon,
                              ),
                              errorWidget: (context, url, error) => AutoArtwork(
                                seed: safeTitle,
                                icon: leadingIcon,
                              ),
                            ),
                    ),
                    if (badgeLabel != null && badgeLabel!.trim().isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppColors.brandOrange)
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeLabel!,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                safeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (hasSubtitle) ...[
                const SizedBox(height: 2),
                Text(
                  safeSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
