/// Live session domain exceptions (safe to show to users).
///
/// Keep these separate from raw DB/network errors — creators should see
/// actionable messages, not internal failures.
class LiveSessionConflictException implements Exception {
  const LiveSessionConflictException(
    this.message, {
    this.existingChannelId,
    this.existingTitle,
    this.existingStartedAt,
  });

  final String message;
  final String? existingChannelId;
  final String? existingTitle;
  final DateTime? existingStartedAt;

  @override
  String toString() => message;
}
