import 'dart:convert';

enum GenerationStatus {
  idle,
  starting,
  processing,
  completed,
  failed;

  String get displayName {
    switch (this) {
      case GenerationStatus.idle:
        return 'Ready';
      case GenerationStatus.starting:
        return 'Starting…';
      case GenerationStatus.processing:
        return 'Generating…';
      case GenerationStatus.completed:
        return 'Completed';
      case GenerationStatus.failed:
        return 'Failed';
    }
  }
}

class SavedBeat {
  const SavedBeat({
    required this.id,
    required this.title,
    required this.style,
    required this.bpm,
    required this.durationSeconds,
    required this.audioUrl,
    required this.createdAt,
    this.localFilePath,
  });

  final String id;
  final String title;
  final String style;
  final int bpm;
  final int durationSeconds;
  final String audioUrl;
  final DateTime createdAt;
  final String? localFilePath;

  SavedBeat copyWith({
    String? localFilePath,
  }) {
    return SavedBeat(
      id: id,
      title: title,
      style: style,
      bpm: bpm,
      durationSeconds: durationSeconds,
      audioUrl: audioUrl,
      createdAt: createdAt,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'style': style,
        'bpm': bpm,
        'duration_seconds': durationSeconds,
        'audio_url': audioUrl,
        'created_at': createdAt.toIso8601String(),
        if (localFilePath != null) 'local_file_path': localFilePath,
      };

  factory SavedBeat.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v, {required int fallback}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? fallback;
    }

    final createdAtRaw = (json['created_at'] ?? json['createdAt'])?.toString();

    return SavedBeat(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      style: (json['style'] ?? '').toString(),
      bpm: asInt(json['bpm'], fallback: 120),
      durationSeconds: asInt(json['duration_seconds'] ?? json['durationSeconds'], fallback: 30),
      audioUrl: (json['audio_url'] ?? json['audioUrl'] ?? '').toString(),
      createdAt: createdAtRaw == null ? DateTime.now() : DateTime.tryParse(createdAtRaw) ?? DateTime.now(),
      localFilePath: (json['local_file_path'] ?? json['localFilePath'])?.toString(),
    );
  }

  static List<SavedBeat> listFromPrefsString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <SavedBeat>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SavedBeat>[];
      return decoded
          .whereType<Map>()
          .map((m) => SavedBeat.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
          .toList(growable: false);
    } catch (_) {
      return const <SavedBeat>[];
    }
  }

  static String listToPrefsString(List<SavedBeat> beats) {
    return jsonEncode(beats.map((b) => b.toJson()).toList(growable: false));
  }
}
