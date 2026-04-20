enum UserRole {
  consumer,
  artist,
  dj,
}

extension UserRoleX on UserRole {
  String get id {
    switch (this) {
      case UserRole.consumer:
        return 'consumer';
      case UserRole.artist:
        return 'artist';
      case UserRole.dj:
        return 'dj';
    }
  }

  String get label {
    switch (this) {
      case UserRole.consumer:
        return 'Consumer';
      case UserRole.artist:
        return 'Artist';
      case UserRole.dj:
        return 'DJ';
    }
  }

  static UserRole fromId(String? value) {
    switch (value) {
      case 'artist':
        return UserRole.artist;
      case 'dj':
        return UserRole.dj;
      case 'user':
        return UserRole.consumer;
      case 'consumer':
      default:
        return UserRole.consumer;
    }
  }
}
