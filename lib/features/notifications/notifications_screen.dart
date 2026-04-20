import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import 'services/notification_center_api.dart';
import 'services/notification_center_store.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = false;
  Object? _error;
  bool _showSearch = false;
  String _query = '';
  bool _usingFallbackSource = false;
  String? _fallbackReason;
  List<NotificationCenterItem> _items = const [];

  List<NotificationCenterItem> get _visibleItems {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q) ||
          n.type.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _usingFallbackSource = false;
      _fallbackReason = null;
    });

    try {
      final items = await NotificationCenterApi.instance.list(limit: 60);
      if (!mounted) return;
      setState(() {
        _items = items;
        _usingFallbackSource = false;
        _fallbackReason = null;
      });
      unawaited(NotificationCenterStore.instance.refreshUnreadCount());
    } catch (e) {
      try {
        final fallback = await _loadFromSupabase(limit: 60);
        if (!mounted) return;
        setState(() {
          _items = fallback;
          _error = null;
          _usingFallbackSource = true;
          _fallbackReason = e.toString();
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<NotificationCenterItem>> _loadFromSupabase({required int limit}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const <NotificationCenterItem>[];
    }

    final rows = await Supabase.instance.client
        .from('notifications')
        .select('id,title,body,type,data,created_at,read_at,read,user_id')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);

    final out = <NotificationCenterItem>[];
    for (final row in (rows as List<dynamic>).whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      out.add(NotificationCenterItem.fromJson(map));
    }
    return out;
  }

  Future<void> _markAllRead() async {
    try {
      await NotificationCenterApi.instance.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (e) => NotificationCenterItem(
                id: e.id,
                title: e.title,
                body: e.body,
                type: e.type,
                data: e.data,
                createdAt: e.createdAt,
                read: true,
                readAt: DateTime.now().toUtc(),
              ),
            )
            .toList(growable: false);
      });
      unawaited(NotificationCenterStore.instance.refreshUnreadCount());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark all as read. Please try again.')),
      );
    }
  }

  Future<void> _markReadBestEffort(NotificationCenterItem item) async {
    if (item.read) return;
    try {
      await NotificationCenterApi.instance.markRead(item.id);
    } catch (_) {
      // Best-effort; still allow UI to proceed.
    }
  }

  String _timeLabel(BuildContext context, DateTime? createdAt) {
    if (createdAt == null) return '';
    final dt = createdAt.toLocal();
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';

    return MaterialLocalizations.of(context).formatShortDate(dt);
  }

  Widget _buildFallbackBanner(BuildContext context) {
    if (!_usingFallbackSource) return const SizedBox.shrink();

    final hint = (_fallbackReason ?? '').trim();
    final subtitle = hint.isEmpty
        ? 'Primary notifications API is unavailable. Showing fallback source.'
        : 'Primary notifications API failed. Showing fallback source.';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.amber.shade100,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search notifications',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  border: InputBorder.none,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _query = '';
              });
            },
            icon: Icon(_showSearch ? Icons.close : Icons.search),
          ),
          TextButton(
            onPressed: _visibleItems.isEmpty ? null : _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Builder(
          builder: (context) {
            if (_loading && _items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_error != null && _items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load notifications. Please try again.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              );
            }

            if (_visibleItems.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildFallbackBanner(context),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _query.trim().isEmpty
                          ? 'No notifications yet.'
                          : 'No notifications match your search.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
              itemCount: _visibleItems.length + (_usingFallbackSource ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (_usingFallbackSource && index == 0) {
                  return _buildFallbackBanner(context);
                }
                final dataIndex = _usingFallbackSource ? index - 1 : index;
                final n = _visibleItems[dataIndex];
                final time = _timeLabel(context, n.createdAt);
                final tileColor = n.read
                    ? AppColors.surface2
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);

                return ListTile(
                  tileColor: tileColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  leading: Icon(
                    n.read ? Icons.notifications_none : Icons.notifications,
                    color: AppColors.textMuted,
                  ),
                  title: Text(
                    n.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: n.read ? FontWeight.w800 : FontWeight.w900,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: n.body.isEmpty
                      ? null
                      : Text(
                          n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                  trailing: time.isEmpty
                      ? null
                      : Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                  onTap: () async {
                    await _markReadBestEffort(n);
                    if (!mounted) return;
                    setState(() {
                      _items = _items
                          .map(
                            (e) => e.id == n.id
                                ? NotificationCenterItem(
                                    id: e.id,
                                    title: e.title,
                                    body: e.body,
                                    type: e.type,
                                    data: e.data,
                                    createdAt: e.createdAt,
                                    read: true,
                                    readAt: DateTime.now().toUtc(),
                                  )
                                : e,
                          )
                          .toList(growable: false);
                    });
                    unawaited(NotificationCenterStore.instance.refreshUnreadCount());
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
