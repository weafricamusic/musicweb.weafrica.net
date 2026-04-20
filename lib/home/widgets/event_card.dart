import 'package:flutter/material.dart';

import '../models/event_model.dart';

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.onPrimaryTap,
    required this.onShare,
  });

  final Event event;
  final VoidCallback onPrimaryTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor = event.isVipAvailable
        ? const Color(0xFF8A2BE2)
        : event.isSellingFast
        ? const Color(0xFF1DB954)
            : const Color(0xFF0096FF);

    final badgeIcon = event.isVipAvailable
      ? Icons.workspace_premium
        : event.isSellingFast
            ? Icons.whatshot
            : Icons.videocam;

    final badgeText = event.isVipAvailable
        ? 'VIP Available'
        : event.isSellingFast
            ? 'Selling Fast'
            : 'Live Stream';

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  event.imageUrl,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: double.infinity,
                      height: 160,
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.event, color: scheme.onSurfaceVariant),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 12, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1DB954), Color(0xFF1ED760)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1DB954).withValues(alpha: 0.30),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        '\$${event.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        event.isVirtual ? '/pass' : '/ticket',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.90),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                _RowDetail(icon: Icons.calendar_today, text: _formatDate(event.date)),
                const SizedBox(height: 6),
                _RowDetail(icon: Icons.location_on, text: event.location),
                const SizedBox(height: 6),
                _RowDetail(icon: Icons.star, text: event.artists.join(' • ')),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPrimaryTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(event.isVirtual ? Icons.play_circle : Icons.confirmation_number, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          event.isVirtual ? 'Join Live' : 'Buy Tickets',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!event.isVirtual)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt, size: 12, color: Color(0xFF1DB954)),
                            const SizedBox(width: 4),
                            Text(
                              '${(event.soldPercent * 100).round()}% sold',
                              style: const TextStyle(
                                color: Color(0xFF1DB954),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    IconButton(
                      onPressed: onShare,
                      icon: const Icon(Icons.share, color: Color(0xFFB3B3B3)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[(dt.month - 1).clamp(0, 11)]} ${dt.day}, ${dt.year}';
  }
}

class _RowDetail extends StatelessWidget {
  const _RowDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF1DB954)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: const Color(0xFFB3B3B3)),
          ),
        ),
      ],
    );
  }
}
