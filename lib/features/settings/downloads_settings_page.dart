import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import 'download_stats.dart';
import 'downloads_storage.dart';

class DownloadsSettingsPage extends StatefulWidget {
  const DownloadsSettingsPage({super.key});

  @override
  State<DownloadsSettingsPage> createState() => _DownloadsSettingsPageState();
}

class _DownloadsSettingsPageState extends State<DownloadsSettingsPage> {
  late Future<List<DownloadedFile>> _future;

  @override
  void initState() {
    super.initState();
    _future = listDownloadedFiles();
  }

  Future<void> _refresh() async {
    setState(() => _future = listDownloadedFiles());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<DownloadStats>(
            future: getDownloadStats(),
            builder: (context, snap) {
              final stats = snap.data;
              final subtitle = stats == null
                  ? 'Calculating…'
                  : stats.fileCount == 0
                      ? 'No downloads'
                      : '${stats.fileCount} files • ${stats.prettySize}';

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.download_for_offline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stored on this device',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(subtitle, style: TextStyle(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (stats != null && stats.fileCount > 0)
                      FilledButton.tonalIcon(
                        onPressed: () => _confirmClear(context),
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Clear'),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'Files',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.0),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<DownloadedFile>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done && !snap.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final files = snap.data ?? const <DownloadedFile>[];
              if (files.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'No downloaded files found.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                );
              }

              final dateFmt = DateFormat.yMMMd().add_jm();
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < files.length; i++) ...[
                      _fileTile(context, files[i], dateFmt),
                      if (i != files.length - 1) Divider(height: 1, color: AppColors.border),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _fileTile(BuildContext context, DownloadedFile f, DateFormat dateFmt) {
    return ListTile(
      dense: true,
      title: Text(
        f.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${f.prettySize} • ${dateFmt.format(f.modified)}',
        style: TextStyle(color: AppColors.textMuted),
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, f),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, DownloadedFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(f.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    final deleted = await deleteDownloadedFile(f.path);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? 'Deleted.' : 'Could not delete.')),
    );
    await _refresh();
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear downloads?'),
        content: const Text('This removes downloaded files from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );

    if (ok != true) return;
    final removed = await clearDownloadedFiles();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(removed == 0 ? 'No downloads to clear.' : 'Removed $removed files.')),
    );
    await _refresh();
    setState(() {}); // refresh stats FutureBuilder
  }
}
