/// Maps user IDs to Agora UIDs and vice versa.
class UidMapper {
  /// Convert a user ID to an Agora UID (integer).
  /// Uses hashCode since Agora SDK requires int UIDs.
  static int userIdToUid(String userId) {
    return userId.hashCode;
  }

  /// The reverse mapping is not stored in UID alone;
  /// use the session participants list for that.
}
