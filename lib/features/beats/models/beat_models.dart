// NOTE: this file intentionally hosts the canonical Beat models.
// The legacy path `lib/features/beat_assistant/models/beat_models.dart` is a shim.

class BeatPreset {
  const BeatPreset({
    required this.style,
    required this.bpm,
    required this.mood,
    required this.duration,
    this.prompt,
    this.key_,
    this.scale,
  });

  final String style;
  final int bpm;
  final String mood;
  final int duration; // seconds
  final String? prompt;

  // Optional music theory hints (backend may ignore).
  final String? key_;
  final String? scale;

  Map<String, dynamic> toJson() => {
        'style': style,
        'bpm': bpm,
        'mood': mood,
        'duration': duration,
        if (prompt != null && prompt!.trim().isNotEmpty) 'prompt': prompt,
        if (key_ != null && key_!.trim().isNotEmpty) 'key': key_,
        if (scale != null && scale!.trim().isNotEmpty) 'scale': scale,
      };

  factory BeatPreset.fromJson(Map<String, dynamic> m) {
    final bpmRaw = m['bpm'];
    final bpm = bpmRaw is num ? bpmRaw.toInt() : int.tryParse('${bpmRaw ?? ''}') ?? 120;

    final durationRaw = m['duration'] ?? m['duration_seconds'] ?? m['durationSeconds'];
    final duration = durationRaw is num ? durationRaw.toInt() : int.tryParse('${durationRaw ?? ''}') ?? 30;

    return BeatPreset(
      style: (m['style'] ?? '').toString(),
      bpm: bpm,
      mood: (m['mood'] ?? '').toString(),
      duration: duration,
      prompt: m['prompt']?.toString(),
      key_: m['key']?.toString() ?? m['key_']?.toString(),
      scale: m['scale']?.toString(),
    );
  }
}

class BeatGenerateRequest {
  const BeatGenerateRequest({
    required this.preset,
    this.seed,
  });

  final BeatPreset preset;
  final int? seed;

  Map<String, dynamic> toJson() => {
        ...preset.toJson(),
        if (seed != null) 'seed': seed,
      };
}

class BeatBattle120Request {
  const BeatBattle120Request({
    required this.style,
    required this.lockedBpm,
    required this.lockedKey,
    required this.sectionTemplate,
    this.mood,
    this.prompt,
    this.seed,
    this.battleId,
    this.fairnessTemplateId,
  });

  final String style;
  final int lockedBpm;
  final String lockedKey;
  final String sectionTemplate;
  final String? mood;
  final String? prompt;
  final int? seed;
  final String? battleId;
  final String? fairnessTemplateId;

  Map<String, dynamic> toJson() => {
        'style': style,
        'locked_bpm': lockedBpm,
        'locked_key': lockedKey,
        'section_template': sectionTemplate,
        if (mood != null && mood!.trim().isNotEmpty) 'mood': mood,
        if (prompt != null && prompt!.trim().isNotEmpty) 'prompt': prompt,
        if (seed != null) 'seed': seed,
        if (battleId != null && battleId!.trim().isNotEmpty) 'battle_id': battleId,
        if (fairnessTemplateId != null && fairnessTemplateId!.trim().isNotEmpty)
          'fairness_template_id': fairnessTemplateId,
      };
}

class BeatGenerateResponse {
  const BeatGenerateResponse({
    required this.prompt,
    required this.sampleRate,
    this.colabMarkdown,
  });

  final String prompt;
  final int sampleRate;
  final String? colabMarkdown;

  factory BeatGenerateResponse.fromJson(Map<String, dynamic> m) {
    final srRaw = m['sample_rate'] ?? m['sampleRate'] ?? 32000;
    final sr = srRaw is num ? srRaw.toInt() : int.tryParse('${srRaw ?? ''}') ?? 32000;

    return BeatGenerateResponse(
      prompt: (m['prompt'] ?? '').toString(),
      sampleRate: sr,
      colabMarkdown: m['colab_markdown']?.toString() ?? m['colabMarkdown']?.toString(),
    );
  }
}

class BeatPaymentRequiredDetails {
  final String action;
  final int coinCost;
  final int creditCost;
  final int coinBalance;
  final int aiCreditBalance;

  const BeatPaymentRequiredDetails({
    required this.action,
    required this.coinCost,
    required this.creditCost,
    required this.coinBalance,
    required this.aiCreditBalance,
  });

  factory BeatPaymentRequiredDetails.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    return BeatPaymentRequiredDetails(
      action: (json['action'] ?? '').toString(),
      coinCost: asInt(json['coin_cost'] ?? json['coinCost']),
      creditCost: asInt(json['credit_cost'] ?? json['creditCost']),
      coinBalance: asInt(json['coin_balance'] ?? json['coinBalance']),
      aiCreditBalance: asInt(json['ai_credit_balance'] ?? json['aiCreditBalance']),
    );
  }
}

class BeatCostEstimate {
  const BeatCostEstimate({
    required this.coinCost,
    required this.creditCost,
    required this.coinBalance,
    required this.aiCreditBalance,
  });

  final int coinCost;
  final int creditCost;
  final int coinBalance;
  final int aiCreditBalance;

  factory BeatCostEstimate.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    return BeatCostEstimate(
      coinCost: asInt(json['coin_cost'] ?? json['coinCost']),
      creditCost: asInt(json['credit_cost'] ?? json['creditCost']),
      coinBalance: asInt(json['coin_balance'] ?? json['coinBalance']),
      aiCreditBalance: asInt(json['ai_credit_balance'] ?? json['aiCreditBalance']),
    );
  }
}

sealed class BeatAssistantException implements Exception {
  String get message;
}

class BeatAssistantOffline implements BeatAssistantException {
  @override
  final String message;

  const BeatAssistantOffline([this.message = 'You appear to be offline.']);

  @override
  String toString() => 'BeatAssistantOffline: $message';
}

class BeatAssistantUnauthorized implements BeatAssistantException {
  @override
  final String message;
  const BeatAssistantUnauthorized(this.message);

  @override
  String toString() => 'BeatAssistantUnauthorized: $message';
}

class BeatAssistantPaymentRequired implements BeatAssistantException {
  @override
  final String message;
  final BeatPaymentRequiredDetails? details;

  const BeatAssistantPaymentRequired(this.message, {this.details});

  @override
  String toString() => 'BeatAssistantPaymentRequired: $message';
}

class BeatAssistantHttpFailure implements BeatAssistantException {
  final int statusCode;
  final String error;
  @override
  final String message;

  const BeatAssistantHttpFailure({
    required this.statusCode,
    required this.error,
    required this.message,
  });

  @override
  String toString() => 'BeatAssistantHttpFailure(HTTP $statusCode, $error): $message';
}

class BeatAudioStartResponse {
  final String jobId;
  final String status;
  final String prompt;
  final Map<String, dynamic>? fairnessLock;

  const BeatAudioStartResponse({
    required this.jobId,
    required this.status,
    required this.prompt,
    this.fairnessLock,
  });

  factory BeatAudioStartResponse.fromJson(Map<String, dynamic> json) {
    final fairnessRaw = json['fairness_lock'];
    Map<String, dynamic>? fairness;
    if (fairnessRaw is Map) {
      fairness = fairnessRaw.map((k, v) => MapEntry(k.toString(), v));
    }

    return BeatAudioStartResponse(
      jobId: (json['job_id'] ?? json['jobId'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      fairnessLock: fairness,
    );
  }
}

class BeatAudioJob {
  final String id;
  final String status;
  final String? audioUrl;
  final String? outputMime;
  final int? outputBytes;
  final String? error;
  final int? durationSeconds;
  final Map<String, dynamic>? fairnessLock;

  const BeatAudioJob({
    required this.id,
    required this.status,
    this.audioUrl,
    this.outputMime,
    this.outputBytes,
    this.error,
    this.durationSeconds,
    this.fairnessLock,
  });

  factory BeatAudioJob.fromJson(Map<String, dynamic> json) {
    int? asIntN(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final fairnessRaw = json['fairness_lock'];
    Map<String, dynamic>? fairness;
    if (fairnessRaw is Map) {
      fairness = fairnessRaw.map((k, v) => MapEntry(k.toString(), v));
    }

    return BeatAudioJob(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      audioUrl: json['audio_url']?.toString() ?? json['audioUrl']?.toString(),
      outputMime: json['output_mime']?.toString() ?? json['outputMime']?.toString(),
      outputBytes: asIntN(json['output_bytes'] ?? json['outputBytes']),
      error: json['error']?.toString(),
      durationSeconds: asIntN(json['duration_seconds'] ?? json['durationSeconds']),
      fairnessLock: fairness,
    );
  }
}

class BeatAudioStatusResponse {
  final BeatAudioJob job;
  const BeatAudioStatusResponse({required this.job});

  factory BeatAudioStatusResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['job'];
    if (raw is Map) {
      final m = raw.map((k, v) => MapEntry(k.toString(), v));
      return BeatAudioStatusResponse(job: BeatAudioJob.fromJson(Map<String, dynamic>.from(m)));
    }
    return BeatAudioStatusResponse(job: BeatAudioJob.fromJson(const <String, dynamic>{}));
  }
}
