import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/firebase_live_service.dart';
import '../../data/repositories/live_session_repository.dart';
import '../../core/models/live_session_model.dart';

/// Shows active live streams and allows starting a new one.
class LiveHomeScreen extends StatefulWidget {
  const LiveHomeScreen({super.key});

  @override
  State<LiveHomeScreen> createState() => _LiveHomeScreenState();
}

class _LiveHomeScreenState extends State<LiveHomeScreen> {
  List<LiveSessionModel> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final repo = LiveSessionRepository(
        FirebaseLiveService(Supabase.instance.client),
      );
      final sessions = await repo.getActiveSessions(limit: 20);
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0617),
      appBar: AppBar(
        title: const Text('Live'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.live_tv, size: 64, color: Colors.white24),
                      SizedBox(height: 16),
                      Text('No live streams right now',
                          style: TextStyle(color: Colors.white54, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (_, i) => _buildSessionCard(_sessions[i]),
                  ),
                ),
    );
  }

  Widget _buildSessionCard(LiveSessionModel session) {
    return Card(
      color: const Color(0xFF1B1530),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red,
          child: const Icon(Icons.person, color: Colors.white),
        ),
        title: Text(session.hostName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text('${session.viewerCount} viewers',
            style: const TextStyle(color: Colors.white54)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('LIVE',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        onTap: () {
          // Navigate to ConsumerLiveScreen — the caller is expected
          // to provide userId/userName from auth context.
        },
      ),
    );
  }
}
