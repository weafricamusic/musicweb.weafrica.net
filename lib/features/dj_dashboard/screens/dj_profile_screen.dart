import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/network/storage_upload_api.dart';
import '../../../app/theme.dart';
import '../../../app/utils/platform_bytes_reader.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../settings/creator_settings_screen.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';
import 'dj_sets_screen.dart';

class DjProfileScreen extends StatefulWidget {
  const DjProfileScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DjProfileScreen> createState() => _DjProfileScreenState();
}

class _DjProfileScreenState extends State<DjProfileScreen> {
  static const String _avatarsBucket = 'dj-avatars';

  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  final _formKey = GlobalKey<FormState>();
  final _stageNameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _mobileMoneyPhoneCtrl = TextEditingController();

  PlatformFile? _avatar;
  String? _existingAvatarUrl;

  List<DjSet> _recentSets = const <DjSet>[];
  List<DjEvent> _upcomingLives = const <DjEvent>[];
  List<DjEvent> _pastLives = const <DjEvent>[];
  List<String> _genreSpecialty = const <String>[];
  num _coinsReceived = 0;
  int _followers = 0;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stageNameCtrl.dispose();
    _countryCtrl.dispose();
    _bioCtrl.dispose();
    _bankAccountCtrl.dispose();
    _mobileMoneyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = _identity.requireDjUid();
      final results = await Future.wait<dynamic>([
        _service.getProfile(djUid: uid),
        _service.listSets(djUid: uid, limit: 10),
        _service.listUpcomingLiveSchedule(djUid: uid, limit: 10),
        _service.listPastLiveSessions(djUid: uid, limit: 10),
        _service.bestEffortCoinsReceived(djUid: uid, limit: 2000),
        _service.bestEffortGenreSpecialty(djUid: uid, setLimit: 200, top: 3),
      ]);

      final profile = results[0] as DjProfile?;
      final sets = results[1] as List<DjSet>;
      final upcoming = results[2] as List<DjEvent>;
      final past = results[3] as List<DjEvent>;
      final coins = results[4] as num;
      final genres = results[5] as List<String>;

      final fb = FirebaseAuth.instance.currentUser;
      final suggested = (profile?.stageName ?? fb?.displayName ?? fb?.email ?? '').trim();

      if (!mounted) return;
      setState(() {
        _stageNameCtrl.text = suggested;
        _countryCtrl.text = (profile?.country ?? '').trim();
        _bioCtrl.text = (profile?.bio ?? '').trim();
        _bankAccountCtrl.text = (profile?.bankAccount ?? '').trim();
        _mobileMoneyPhoneCtrl.text = (profile?.mobileMoneyPhone ?? '').trim();
        _existingAvatarUrl = (profile?.profilePhoto ?? fb?.photoURL)?.trim();
        _recentSets = sets;
        _upcomingLives = upcoming;
        _pastLives = past;
        _coinsReceived = coins;
        _followers = profile?.followersCount ?? 0;
        _genreSpecialty = genres;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load profile.';
      });
    }
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return 'TBA';
    final local = dt.toLocal();
    return DateFormat('EEE, MMM d • HH:mm').format(local);
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w900),
    );
  }

  Widget _infoRow({
    IconData? icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }

  Future<void> _openReplay(DjEvent e) async {
    final raw = e.replayUrl;
    if (raw == null || raw.trim().isEmpty) return;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return;

    // Keep it simple: open externally.
    // (The app already uses video_player elsewhere, but replay formats/hosts vary.)
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (!mounted) return;
    setState(() {
      _avatar = result?.files.single;
    });
  }

  String _safeFilename(String? name, {required String fallbackExt}) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'file.$fallbackExt';
    return n.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  Future<String?> _uploadAvatarIfNeeded({required String uid}) async {
    final file = _avatar;
    if (file == null) return null;

    final bytes = await readPlatformFileBytes(file);
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;

    final ext = (() {
      final n = file.name.toLowerCase();
      final dot = n.lastIndexOf('.');
      if (dot > 0 && dot < n.length - 1) return n.substring(dot + 1);
      return 'jpg';
    })();

    final filename = _safeFilename(file.name, fallbackExt: ext);

    final result = await StorageUploadApi.upload(
      bucket: _avatarsBucket,
      prefix: 'dj-profile/$uid/$ts',
      fileName: '$ts-$filename',
      fileBytes: bytes,
      timeout: const Duration(minutes: 10),
    );

    return result.bestUrl;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to edit your profile.')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final uid = _identity.requireDjUid();
      String? avatarUrl;

      try {
        avatarUrl = await _uploadAvatarIfNeeded(uid: uid);
      } on StorageException catch (e, st) {
        UserFacingError.log('DjProfileScreen avatar upload failed', e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Avatar upload failed. Please try again.')),
          );
        }
      }

      final stageName = _stageNameCtrl.text.trim();
      final country = _countryCtrl.text.trim();
      final bio = _bioCtrl.text.trim();
      final bankAccount = _bankAccountCtrl.text.trim();
      final mobileMoneyPhone = _mobileMoneyPhoneCtrl.text.trim();

      await _service.upsertProfile(
        djUid: uid,
        stageName: stageName.isEmpty ? null : stageName,
        country: country.isEmpty ? null : country,
        bio: bio.isEmpty ? null : bio,
        profilePhoto: avatarUrl,
        bankAccount: bankAccount.isEmpty ? null : bankAccount,
        mobileMoneyPhone: mobileMoneyPhone.isEmpty ? null : mobileMoneyPhone,
      );

      if (stageName.isNotEmpty && stageName != (fb.displayName ?? '')) {
        await fb.updateDisplayName(stageName);
      }
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty && avatarUrl != (fb.photoURL ?? '')) {
        await fb.updatePhotoURL(avatarUrl);
      }

      if (!mounted) return;
      setState(() {
        _existingAvatarUrl = avatarUrl ?? _existingAvatarUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (e, st) {
      UserFacingError.log('DjProfileScreen save failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() { _saving = false; });
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreatorSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((_error ?? '').isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(_error!, style: const TextStyle(color: AppColors.textMuted)),
                  ),
                  const SizedBox(height: 12),
                ],

                _card(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.surface,
                        backgroundImage: (_existingAvatarUrl ?? '').trim().isNotEmpty
                            ? NetworkImage(_existingAvatarUrl!)
                            : null,
                        child: (_existingAvatarUrl ?? '').trim().isNotEmpty
                            ? null
                            : const Icon(Icons.person_outline, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Profile photo', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(
                              _avatar?.name ?? 'Tap to pick a photo',
                              style: const TextStyle(color: AppColors.textMuted),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _saving ? null : _pickAvatar,
                        child: const Text('Choose'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _sectionTitle('Public DJ profile'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _stageNameCtrl.text.trim().isEmpty
                                  ? 'DJ'
                                  : _stageNameCtrl.text.trim(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            '👥 $_followers',
                            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _MiniStat(label: 'Mixes', value: _recentSets.length.toString()),
                          _MiniStat(label: 'Coins', value: _coinsReceived.toStringAsFixed(0)),
                          _MiniStat(label: 'Upcoming lives', value: _upcomingLives.length.toString()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Genre specialty',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (_genreSpecialty.isEmpty)
                        const Text('Not set yet', style: TextStyle(color: AppColors.textMuted))
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _genreSpecialty
                              .map(
                                (g) => Chip(
                                  label: Text(g),
                                  side: const BorderSide(color: AppColors.border),
                                  backgroundColor: AppColors.surface,
                                ),
                              )
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _sectionTitle('Mixes uploaded'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    children: [
                      if (_recentSets.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No mixes uploaded yet.', style: TextStyle(color: AppColors.textMuted)),
                        )
                      else
                        ..._recentSets.map((s) {
                          final subtitleParts = <String>[];
                          final g = (s.genre ?? '').trim();
                          if (g.isNotEmpty) subtitleParts.add(g);
                          subtitleParts.add('${s.plays} plays');
                          subtitleParts.add('${s.coinsEarned} coins');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _infoRow(
                              icon: Icons.library_music_outlined,
                              title: s.title,
                              subtitle: subtitleParts.join(' • '),
                            ),
                          );
                        }),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const DjSetsScreen()),
                            );
                          },
                          child: const Text('View all mixes'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _sectionTitle('Live sessions schedule'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_upcomingLives.isEmpty)
                        const Text('No scheduled live sessions.', style: TextStyle(color: AppColors.textMuted))
                      else
                        ..._upcomingLives.map((e) {
                          final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
                          final when = '${_fmtDate(e.startsAt)} → ${_fmtDate(e.endsAt)}';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _infoRow(
                              icon: Icons.event_outlined,
                              title: title,
                              subtitle: when,
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                _sectionTitle('Past live replays'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_pastLives.isEmpty)
                        const Text('No past live sessions yet.', style: TextStyle(color: AppColors.textMuted))
                      else
                        ..._pastLives.map((e) {
                          final title = (e.title ?? '').trim().isEmpty ? 'Live session' : e.title!.trim();
                          final when = _fmtDate(e.startsAt);
                          final replay = e.replayUrl;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _infoRow(
                              icon: Icons.play_circle_outline,
                              title: title,
                              subtitle: replay == null ? '$when • Replay not uploaded' : '$when • Replay available',
                              trailing: replay == null
                                  ? null
                                  : TextButton(
                                      onPressed: () => _openReplay(e),
                                      child: const Text('Watch'),
                                    ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _stageNameCtrl,
                        decoration: const InputDecoration(labelText: 'Stage name'),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'Enter a stage name';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(labelText: 'Country'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _bioCtrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(labelText: 'Bio'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _bankAccountCtrl,
                        decoration: const InputDecoration(labelText: 'Bank account (for withdrawals)'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _mobileMoneyPhoneCtrl,
                        decoration: const InputDecoration(labelText: 'Mobile money phone number (for withdrawals)'),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    if (!widget.showAppBar) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('DJ Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          TextButton(
            onPressed: (_saving || _loading) ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
