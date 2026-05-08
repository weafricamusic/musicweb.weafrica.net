// ── Barrel: conditional platform exports ──
// Shared types (AgoraConfig, AgoraRole) ─ always available
export 'agora_service_shared.dart';

// AgoraService class ─ web: full SDK, native: stub
export 'agora_service_native.dart'
    if (dart.library.html) 'agora_service_web_full.dart';