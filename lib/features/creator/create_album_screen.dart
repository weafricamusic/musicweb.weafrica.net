import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';
import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import 'add_album_tracks_screen.dart';

class CreateAlbumScreen extends StatefulWidget {
  const CreateAlbumScreen({super.key});

  @override
  State<CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (firebaseUid.isEmpty) {
        throw StateError('You must be signed in to create an album.');
      }

      final title = _titleCtrl.text.trim();
      final description = _descCtrl.text.trim();

      final uri = Uri.parse('${ApiEnv.baseUrl}/api/albums/create');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          if (description.isNotEmpty) 'description': description,
          'publish': false,
        }),
        timeout: const Duration(seconds: 15),
        requireAuth: true,
      );

      if (res.statusCode == 404) {
        UserFacingError.log('CreateAlbumScreen._submit', 'Create album endpoint not found (HTTP 404).');
        throw StateError('Album service is temporarily unavailable. Please try again.');
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        UserFacingError.log('CreateAlbumScreen._submit', 'Create album failed (HTTP ${res.statusCode}).');
        var msg = 'Could not create album. Please try again.';
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            msg = (decoded['message'] ?? decoded['error'] ?? msg).toString();
          }
        } catch (_) {
          final t = res.body.trim();
          if (t.isNotEmpty) msg = t;
        }
        throw StateError(msg);
      }

      final decoded = jsonDecode(res.body);
      final albumId = decoded is Map ? (decoded['album_id'] ?? '').toString().trim() : '';
      if (albumId.isEmpty) {
        throw StateError('Album created, but no album id was returned.');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AddAlbumTracksScreen(albumId: albumId, albumTitle: title),
        ),
      );
    } catch (e, st) {
      UserFacingError.log('CreateAlbumScreen._submit', e, st);
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not create album. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create album')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Create a new album',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Add album details now. Track-level publishing can continue with Upload Single.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Album title'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter album title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Tell listeners about this album',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.album),
              label: Text(_loading ? 'Creating…' : 'Create album'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink),
            ),
          ),
        ],
      ),
    );
  }
}
