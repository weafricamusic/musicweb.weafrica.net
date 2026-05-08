import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/agora_constants.dart';
import '../../core/enums/live_role.dart';

/// Fetches Agora tokens from the backend edge function.
class AgoraTokenService {
  /// Fetch a token for a given channel and role.
  static Future<String> fetchToken({
    required String channelName,
    required LiveRole role,
    int uid = 0,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AgoraConstants.tokenServerUrl}?channel=$channelName&uid=$uid&role=${role.name}',
        ),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['token'] ?? '';
      }
    } catch (e) {
      // Token fetch failure is non-fatal — Agora allows joining without a token
      // when the channel is configured for app-level authentication.
    }
    return '';
  }
}
