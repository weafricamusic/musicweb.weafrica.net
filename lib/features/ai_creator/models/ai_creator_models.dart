class AiCreatorGeneration {
  const AiCreatorGeneration({
    required this.id,
    required this.status,
    required this.createdAt,
    this.resultAudioUrl,
    this.title,
    this.prompt,
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final String? resultAudioUrl;

  // Optional display fields (best-effort, depends on backend shape).
  final String? title;
  final String? prompt;

  bool get isReady => (resultAudioUrl ?? '').trim().isNotEmpty;

  static AiCreatorGeneration fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['generation_id'] ?? json['generationId'] ?? json['job_id'] ?? json['jobId'] ?? '')
        .toString()
        .trim();

    final status = (json['status'] ?? json['state'] ?? 'unknown').toString().trim();

    DateTime createdAt = DateTime.now();
    final rawCreated = json['created_at'] ?? json['createdAt'] ?? json['requested_at'] ?? json['requestedAt'];
    if (rawCreated is String) {
      createdAt = DateTime.tryParse(rawCreated) ?? createdAt;
    } else if (rawCreated is int) {
      // seconds or millis.
      createdAt = rawCreated > 2000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawCreated)
          : DateTime.fromMillisecondsSinceEpoch(rawCreated * 1000);
    }

    final resultAudioUrl = (json['result_audio_url'] ?? json['resultAudioUrl'] ?? json['audio_url'] ?? json['audioUrl'] ?? json['result_url'] ?? json['resultUrl'])
        ?.toString()
        .trim();

    final title = (json['title'] ?? '').toString().trim();
    final prompt = (json['prompt'] ?? '').toString().trim();

    return AiCreatorGeneration(
      id: id.isEmpty ? '(unknown)' : id,
      status: status.isEmpty ? 'unknown' : status,
      createdAt: createdAt,
      resultAudioUrl: (resultAudioUrl == null || resultAudioUrl.isEmpty) ? null : resultAudioUrl,
      title: title.isEmpty ? null : title,
      prompt: prompt.isEmpty ? null : prompt,
    );
  }
}

class AiCreatorStartRequest {
  const AiCreatorStartRequest({
    required this.prompt,
    this.title,
    this.genre,
    this.mood,
    this.type,
    this.lengthSeconds,
  });

  final String prompt;
  final String? title;
  final String? genre;
  final String? mood;
  final String? type;
  final int? lengthSeconds;

  Map<String, Object?> toJson() {
    return {
      'prompt': prompt,
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if ((genre ?? '').trim().isNotEmpty) 'genre': genre!.trim(),
      if ((mood ?? '').trim().isNotEmpty) 'mood': mood!.trim(),
      if ((type ?? '').trim().isNotEmpty) 'type': type!.trim(),
      if (lengthSeconds != null) 'length_seconds': lengthSeconds,
    };
  }
}
