import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/network/storage_upload_api.dart';
import '../../../app/theme.dart';
import '../../../app/utils/platform_bytes_reader.dart';
import '../../../app/utils/user_facing_error.dart';
import '../services/artist_identity_service.dart';

class ArtistProfileSettingsScreen extends StatefulWidget {
  const ArtistProfileSettingsScreen({
    super.key,
    this.showAppBar = true,
  });

  /// When false, renders only the scrollable body so the screen can be embedded
  /// inside another Scaffold (e.g. Studio dashboard) without a nested AppBar.
  final bool showAppBar;

  @override
  State<ArtistProfileSettingsScreen> createState() => _ArtistProfileSettingsScreenState();
}

class _ArtistProfileSettingsScreenState extends State<ArtistProfileSettingsScreen> {
  final _identity = ArtistIdentityService();

  static const String _imagesBucket = 'avatars';

  final _formKey = GlobalKey<FormState>();

  final _avatarUrlCtrl = TextEditingController();
  final _coverUrlCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _genresCtrl = TextEditingController();

  final _igCtrl = TextEditingController();
  final _fbCtrl = TextEditingController();
  final _ttCtrl = TextEditingController();
  final _ytCtrl = TextEditingController();
  final _scCtrl = TextEditingController();
  final _spCtrl = TextEditingController();
  final _webCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;
  String? _artistId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _avatarUrlCtrl.dispose();
    _coverUrlCtrl.dispose();
    _bioCtrl.dispose();
    _genresCtrl.dispose();

    _igCtrl.dispose();
    _fbCtrl.dispose();
    _ttCtrl.dispose();
    _ytCtrl.dispose();
    _scCtrl.dispose();
    _spCtrl.dispose();
    _webCtrl.dispose();

    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final client = Supabase.instance.client;

    final uid = _identity.currentFirebaseUid();
    final artistId = await _identity.resolveArtistIdForCurrentUser();

    Map<String, dynamic>? creatorProfile;
    Map<String, dynamic>? artistRow;

    if ((uid ?? '').trim().isNotEmpty) {
      try {
        final List<Map<String, dynamic>> rows = await client
            .from('creator_profiles')
            .select('*')
            .eq('user_id', uid!)
            .limit(1);
        if (rows.isNotEmpty) creatorProfile = rows.first;
      } catch (_) {
        // ignore
      }
    }

    if ((artistId ?? '').trim().isNotEmpty) {
      try {
        final List<Map<String, dynamic>> rows = await client
            .from('artists')
            .select('*')
            .eq('id', artistId!)
            .limit(1);
        if (rows.isNotEmpty) artistRow = rows.first;
      } catch (_) {
        // ignore
      }
    }

    String readString(Map<String, dynamic>? row, List<String> keys) {
      if (row == null) return '';
      for (final key in keys) {
        final v = (row[key] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final fb = FirebaseAuth.instance.currentUser;

    if (!mounted) return;
    setState(() {
      _artistId = artistId;
      _avatarUrlCtrl.text = readString(creatorProfile, const ['avatar_url'])
          .trim()
          .isNotEmpty
          ? readString(creatorProfile, const ['avatar_url'])
          : ((fb?.photoURL ?? '').trim());
      _coverUrlCtrl.text = readString(creatorProfile, const ['cover_url', 'cover_image_url', 'banner_url']);
      _bioCtrl.text = readString(creatorProfile, const ['bio']);
      _genresCtrl.text = readString(artistRow, const ['genre', 'genres']);

      _igCtrl.text = readString(artistRow, const ['instagram_url', 'instagram', 'ig_url', 'ig']);
      _fbCtrl.text = readString(artistRow, const ['facebook_url', 'facebook', 'fb_url', 'fb']);
      _ttCtrl.text = readString(artistRow, const ['tiktok_url', 'tiktok', 'tt_url', 'tt']);
      _ytCtrl.text = readString(artistRow, const ['youtube_url', 'youtube', 'yt_url', 'yt']);
      _scCtrl.text = readString(artistRow, const ['soundcloud_url', 'soundcloud', 'sc_url', 'sc']);
      _spCtrl.text = readString(artistRow, const ['spotify_url', 'spotify', 'sp_url', 'sp']);
      _webCtrl.text = readString(artistRow, const ['website_url', 'website', 'site_url', 'url']);

      _loading = false;
    });
  }

  String? _validateUrlOrEmpty(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null || (!uri.hasScheme && !v.startsWith('www.'))) {
      return 'Enter a valid URL';
    }
    return null;
  }

  String _safeFilename(String? name, {required String fallbackExt}) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'file.$fallbackExt';
    return n.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  Future<void> _pickAndUploadImage({required bool isCover}) async {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) {
      _snack('Please sign in to upload images.');
      return;
    }

    final uid = _identity.currentFirebaseUid();
    if (uid == null) {
      _snack('Could not resolve your account id.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    final file = result?.files.single;
    if (file == null) return;

    setState(() {
      if (isCover) {
        _uploadingCover = true;
      } else {
        _uploadingAvatar = true;
      }
    });

    try {
      final bytes = await readPlatformFileBytes(file);
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch;

      final ext = (() {
        final n = file.name.toLowerCase();
        final dot = n.lastIndexOf('.');
        if (dot > 0 && dot < n.length - 1) return n.substring(dot + 1);
        return 'jpg';
      })();

      final filename = _safeFilename(file.name, fallbackExt: ext);
      final kind = isCover ? 'cover' : 'avatar';

      final upload = await StorageUploadApi.upload(
        bucket: _imagesBucket,
        prefix: 'artist-profile/$uid/$kind/$ts',
        fileName: '$ts-$filename',
        fileBytes: bytes,
        timeout: const Duration(minutes: 10),
      );

      if (!mounted) return;
      setState(() {
        if (isCover) {
          _coverUrlCtrl.text = upload.bestUrl;
        } else {
          _avatarUrlCtrl.text = upload.bestUrl;
        }
      });

      // Best-effort: if they uploaded a new avatar, keep Firebase photoURL in sync.
      if (!isCover) {
        try {
          await fb.updatePhotoURL(upload.bestUrl);
          await fb.reload();
        } catch (_) {
          // ignore
        }
      }
    } catch (e, st) {
      UserFacingError.log('ArtistProfileSettingsScreen uploadImage failed', e, st);
      _snack('Upload failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          if (isCover) {
            _uploadingCover = false;
          } else {
            _uploadingAvatar = false;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) {
      _snack('Please sign in to edit your profile.');
      return;
    }

    setState(() => _saving = true);

    final client = Supabase.instance.client;
    final uid = _identity.currentFirebaseUid();
    final artistId = _artistId;

    final avatarUrl = _avatarUrlCtrl.text.trim();
    final coverUrl = _coverUrlCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final genres = _genresCtrl.text.trim();

    final updatesCreator = <String, Object>{
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
      if (bio.isNotEmpty) 'bio': bio,
    };

    final hasArtistFields = genres.isNotEmpty ||
        _igCtrl.text.trim().isNotEmpty ||
        _fbCtrl.text.trim().isNotEmpty ||
        _ttCtrl.text.trim().isNotEmpty ||
        _ytCtrl.text.trim().isNotEmpty ||
        _scCtrl.text.trim().isNotEmpty ||
        _spCtrl.text.trim().isNotEmpty ||
        _webCtrl.text.trim().isNotEmpty;

    bool creatorOk = true;
    bool artistsOk = true;

    try {
      if ((uid ?? '').trim().isNotEmpty) {
        // Upsert by user_id so new profiles get created.
        await client.from('creator_profiles').upsert(
          <String, Object>{
            'user_id': uid!,
            ...updatesCreator,
          },
          onConflict: 'user_id',
        );
      } else if (updatesCreator.isNotEmpty) {
        creatorOk = false;
      }
    } catch (_) {
      creatorOk = false;
    }

    try {
      if ((artistId ?? '').trim().isNotEmpty) {
        final updateArtist = <String, Object>{
          if (genres.isNotEmpty) 'genre': genres,
          if (_igCtrl.text.trim().isNotEmpty) 'instagram_url': _igCtrl.text.trim(),
          if (_fbCtrl.text.trim().isNotEmpty) 'facebook_url': _fbCtrl.text.trim(),
          if (_ttCtrl.text.trim().isNotEmpty) 'tiktok_url': _ttCtrl.text.trim(),
          if (_ytCtrl.text.trim().isNotEmpty) 'youtube_url': _ytCtrl.text.trim(),
          if (_scCtrl.text.trim().isNotEmpty) 'soundcloud_url': _scCtrl.text.trim(),
          if (_spCtrl.text.trim().isNotEmpty) 'spotify_url': _spCtrl.text.trim(),
          if (_webCtrl.text.trim().isNotEmpty) 'website_url': _webCtrl.text.trim(),
        };

        if (updateArtist.isNotEmpty) {
          await client.from('artists').update(updateArtist).eq('id', artistId!);
        }
      } else if (hasArtistFields) {
        artistsOk = false;
      }
    } catch (_) {
      artistsOk = false;
    }

    // Keep Firebase photoURL in sync if provided.
    try {
      final current = (fb.photoURL ?? '').trim();
      if (avatarUrl != current) {
        await fb.updatePhotoURL(avatarUrl.isEmpty ? null : avatarUrl);
        await fb.reload();
      }
    } catch (_) {
      // best-effort
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (creatorOk && artistsOk) {
      _snack('Profile updated.');
      if (widget.showAppBar) {
        Navigator.of(context).maybePop();
      }
    } else {
      _snack('Saved with limitations. Some fields could not be saved yet.');
    }
  }

  Widget _imageCard({
    required String title,
    required TextEditingController controller,
    required IconData icon,
    required bool isCover,
  }) {
    final url = controller.text.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: (isCover ? _uploadingCover : _uploadingAvatar)
                  ? null
                  : () => _pickAndUploadImage(isCover: isCover),
              icon: (isCover ? _uploadingCover : _uploadingAvatar)
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: Text((isCover ? _uploadingCover : _uploadingAvatar)
                  ? 'Uploading…'
                  : 'Choose & upload'),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: isCover ? 4 : 1,
              child: Container(
                color: AppColors.surface,
                child: url.isEmpty
                    ? Center(child: Icon(icon, color: AppColors.textMuted, size: 34))
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, err, st) {
                          return Center(child: Icon(Icons.broken_image, color: AppColors.textMuted, size: 34));
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _sectionTitle('Profile picture'),
                const SizedBox(height: 10),
                _imageCard(
                  title: 'Profile picture',
                  controller: _avatarUrlCtrl,
                  icon: Icons.person,
                  isCover: false,
                ),

                const SizedBox(height: 16),
                _sectionTitle('Cover image'),
                const SizedBox(height: 10),
                _imageCard(
                  title: 'Cover image',
                  controller: _coverUrlCtrl,
                  icon: Icons.image,
                  isCover: true,
                ),

                const SizedBox(height: 16),
                _sectionTitle('Bio'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextFormField(
                    controller: _bioCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Tell fans about your music…',
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _sectionTitle('Social links'),
                const SizedBox(height: 10),
                _linksCard(),

                const SizedBox(height: 16),
                _sectionTitle('Genre(s)'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextFormField(
                    controller: _genresCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Genres',
                      hintText: 'e.g. Afrobeat, Gospel, Amapiano',
                    ),
                  ),
                ),

                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save changes'),
                  ),
                ),
              ],
            ),
          );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _linksCard() {
    InputDecoration d(String label) => InputDecoration(labelText: label, hintText: 'https://…');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TextFormField(controller: _igCtrl, decoration: d('Photo Feed'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
          const SizedBox(height: 10),
          TextFormField(controller: _fbCtrl, decoration: d('Facebook'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
          const SizedBox(height: 10),
          TextFormField(controller: _ttCtrl, decoration: d('Short Video'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
          const SizedBox(height: 10),
          TextFormField(controller: _ytCtrl, decoration: d('YouTube'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
          const SizedBox(height: 10),
          TextFormField(controller: _scCtrl, decoration: d('SoundCloud'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
          const SizedBox(height: 10),
          TextFormField(controller: _spCtrl, decoration: d('Spotify'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
          const SizedBox(height: 10),
          TextFormField(controller: _webCtrl, decoration: d('Website'), keyboardType: TextInputType.url, validator: _validateUrlOrEmpty),
        ],
      ),
    );
  }
}
