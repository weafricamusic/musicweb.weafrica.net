import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _displayNameController = TextEditingController();
  final _photoUrlController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _displayNameController.text = (user?.displayName ?? '').trim();
    _photoUrlController.text = (user?.photoURL ?? '').trim();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to edit your profile.')),
      );
      return;
    }

    final displayName = _displayNameController.text.trim();
    final photoUrl = _photoUrlController.text.trim();

    setState(() => _saving = true);
    try {
      if (displayName != user.displayName) {
        await user.updateDisplayName(displayName.isEmpty ? null : displayName);
      }
      if (photoUrl != user.photoURL) {
        await user.updatePhotoURL(photoUrl.isEmpty ? null : photoUrl);
      }

      await user.reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      Navigator.of(context).maybePop();
    } catch (e, st) {
      UserFacingError.log('EditProfileScreen._save', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              e,
              fallback: 'Could not update profile. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'EDIT PROFILE',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'e.g. WeAfrica Fan',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _photoUrlController,
            decoration: const InputDecoration(
              labelText: 'Photo URL',
              hintText: 'https://…',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text(
                'SAVE',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
