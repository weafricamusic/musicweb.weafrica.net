import 'dart:convert';

/// Best-effort JWT payload decoder for debugging.
///
/// Safe to log selected claims (iss/aud/sub/exp) but never log the raw token.
Map<String, dynamic>? tryDecodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;

    final normalized = base64Url.normalize(parts[1]);
    final bytes = base64Url.decode(normalized);
    final decoded = utf8.decode(bytes);
    final obj = jsonDecode(decoded);

    if (obj is Map<String, dynamic>) return obj;
    if (obj is Map) {
      return obj.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Human-readable summary of common Firebase ID token claims.
String firebaseJwtSummary(String token) {
  final p = tryDecodeJwtPayload(token);
  final iss = p?['iss']?.toString() ?? '-';
  final aud = p?['aud']?.toString() ?? '-';
  final sub = p?['sub']?.toString() ?? '-';
  final exp = p?['exp']?.toString() ?? '-';
  return 'iss=$iss aud=$aud sub=$sub exp=$exp';
}
