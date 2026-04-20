import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../auth/user_role.dart';
import '../../profile/role_based_profile_screen.dart';
import '../../tracks/track.dart';
import '../../tracks/tracks_repository.dart';
import '../data/photo_song_posts_repository.dart';

class PhotoSongPostMockupScreen extends StatefulWidget {
  const PhotoSongPostMockupScreen({
    super.key,
    required this.role,
    this.initialSongId,
    this.initialSongStartSeconds,
    this.initialSongDurationSeconds,
  });

  final UserRole role;

  /// When provided, the screen will preselect this song.
  final String? initialSongId;

  /// Optional defaults for the song clip when preselecting a song.
  final int? initialSongStartSeconds;
  final int? initialSongDurationSeconds;

  @override
  State<PhotoSongPostMockupScreen> createState() =>
      _PhotoSongPostMockupScreenState();
}

class _PhotoSongPostMockupScreenState extends State<PhotoSongPostMockupScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final PhotoSongPostsRepository _postsRepository = PhotoSongPostsRepository();
  final TracksRepository _tracksRepository = TracksRepository();

  XFile? _selectedImage;
  Track? _selectedTrack;
  int _songStartSeconds = 0;
  int _songDurationSeconds = 15;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_maybeHydrateInitialSong());
  }

  Future<void> _maybeHydrateInitialSong() async {
    final id = (widget.initialSongId ?? '').trim();
    if (id.isEmpty) return;

    try {
      final track = await _tracksRepository.getById(id);
      if (!mounted) return;
      if (track == null) return;

      setState(() {
        _selectedTrack = track;
        _songStartSeconds = (widget.initialSongStartSeconds ?? 0).clamp(0, 60);
        _songDurationSeconds = (widget.initialSongDurationSeconds ?? 15).clamp(15, 30);
      });
    } catch (_) {
      // Non-fatal; user can pick manually.
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null || !mounted) return;
    setState(() => _selectedImage = picked);
  }

  Future<void> _pickSong() async {
    final selected = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _SongPickerSheet(),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _selectedTrack = selected;
      _songStartSeconds = 0;
      _songDurationSeconds = 15;
    });
  }

  Future<void> _publish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Please sign in to publish.')),
        );
      return;
    }

    if (_selectedImage == null || _selectedTrack == null) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Select a picture and a song first.'),
          ),
        );
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await _postsRepository.createPost(
        creatorUid: user.uid,
        image: _selectedImage!,
        song: _selectedTrack!,
        caption: _captionController.text,
        songStartSeconds: _songStartSeconds,
        songDurationSeconds: _songDurationSeconds,
      );
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Post published successfully.')),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Publish failed: $e')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? 'Creator').trim();
    final username = name.isEmpty ? 'Creator' : name;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Photo + Song Post'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _buildComposerCard(),
          const SizedBox(height: 14),
          _buildPreviewCard(username: username, user: user),
        ],
      ),
    );
  }

  Widget _buildComposerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Post',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
              FilledButton.tonalIcon(
                onPressed: _pickSong,
                icon: const Icon(Icons.music_note_outlined),
                label: Text(_selectedTrack == null
                    ? 'Select Song'
                  : _selectedTrack!.title),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _captionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Caption (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedTrack != null) ...[
            Text(
              'Song Clip',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Text('Start: $_songStartSeconds   Duration: $_songDurationSeconds'),
            Slider(
              min: 0,
              max: 60,
              divisions: 12,
              value: _songStartSeconds.toDouble(),
              label: '$_songStartSeconds',
              onChanged: (v) => setState(() => _songStartSeconds = v.round()),
            ),
            Slider(
              min: 15,
              max: 30,
              divisions: 3,
              value: _songDurationSeconds.toDouble(),
              label: '$_songDurationSeconds',
              onChanged: (v) => setState(() => _songDurationSeconds = v.round()),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isPublishing ? null : _publish,
              icon: _isPublishing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish_outlined),
              label: const Text('Publish Post'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard({required String username, required User? user}) {
    final avatar = (user?.photoURL ?? '').trim();
    final caption = _captionController.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RoleBasedProfileScreen(roleOverride: widget.role),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    foregroundImage:
                        avatar.isEmpty ? null : NetworkImage(avatar),
                    child: avatar.isEmpty ? const Icon(Icons.person, size: 16) : null,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RoleBasedProfileScreen(roleOverride: widget.role),
                    ),
                  ),
                  child: Text(
                    username,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Following'),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_selectedImage != null)
                  Image.file(
                    File(_selectedImage!.path),
                    fit: BoxFit.cover,
                  )
                else
                  Container(
                    color: AppColors.surface2,
                    alignment: Alignment.center,
                    child: const Text('Preview image'),
                  ),
                if (_selectedTrack != null)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '♫ ${_selectedTrack!.title} • ${_selectedTrack!.artist}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite_border),
                    const SizedBox(width: 14),
                    const Icon(Icons.chat_bubble_outline),
                    const SizedBox(width: 14),
                    const Icon(Icons.send_outlined),
                    const Spacer(),
                    const Icon(Icons.bookmark_border),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1,024 likes',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$username ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: caption),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SongPickerSheet extends StatefulWidget {
  const _SongPickerSheet();

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TracksRepository _tracksRepository = TracksRepository();

  Future<List<Track>>? _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = _tracksRepository.latest(limit: 40);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    setState(() {
      _songsFuture = value.trim().isEmpty
          ? _tracksRepository.latest(limit: 40)
          : _tracksRepository.search(value, limit: 40);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'Search songs...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 360,
              child: FutureBuilder<List<Track>>(
                future: _songsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Could not load songs right now.'),
                    );
                  }

                  final songs = snapshot.data ?? const <Track>[];
                  if (songs.isEmpty) {
                    return const Center(child: Text('No songs found.'));
                  }

                  return ListView.separated(
                    itemCount: songs.length,
                    separatorBuilder: (context, index) => Divider(color: AppColors.border),
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return ListTile(
                        leading: CircleAvatar(
                          foregroundImage: song.artworkUri == null
                              ? null
                              : NetworkImage(song.artworkUri.toString()),
                          child: song.artworkUri == null
                              ? const Icon(Icons.music_note)
                              : null,
                        ),
                        title: Text(song.title),
                        subtitle: Text(song.artist),
                        onTap: () => Navigator.of(context).pop(song),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
