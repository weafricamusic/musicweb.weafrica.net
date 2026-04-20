import 'package:firebase_auth/firebase_auth.dart';

class DjIdentityService {
  final FirebaseAuth _auth;

  DjIdentityService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  String requireDjUid() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    return user.uid;
  }
}
