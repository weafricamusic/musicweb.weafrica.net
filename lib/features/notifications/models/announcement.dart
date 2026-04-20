class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final DateTime? createdAt;

  factory Announcement.fromSupabase(Map<String, dynamic> row) {
    String s(dynamic v) => (v ?? '').toString().trim();

    final id = s(row['id'] ?? row['announcement_id'] ?? row['uuid']);
    final title = s(row['title'] ?? row['heading']);
    final message = s(row['message'] ?? row['body'] ?? row['content']);
    final createdAt = _parseDate(row['created_at'] ?? row['createdAt'] ?? row['timestamp']);

    return Announcement(
      id: id,
      title: title,
      message: message,
      createdAt: createdAt,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
