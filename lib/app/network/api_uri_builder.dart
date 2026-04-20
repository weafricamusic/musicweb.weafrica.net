import '../config/api_env.dart';
import '../config/app_env.dart';

/// Centralized URI builder for app API calls.
///
/// This keeps infra concerns (like Vercel protection bypass) out of feature APIs.
class ApiUriBuilder {
  const ApiUriBuilder();

  Uri build(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final base = Uri.tryParse(ApiEnv.baseUrl);
    final qp = <String, String>{
      if (queryParameters != null) ...queryParameters,
    };

    final bypass = AppEnv.vercelProtectionBypassToken.trim();
    final isVercel = base != null && base.host.endsWith('vercel.app');
    if (isVercel && bypass.isNotEmpty) {
      qp['x-vercel-set-bypass-cookie'] = 'true';
      qp['x-vercel-protection-bypass'] = bypass;
    }

    final u = Uri.parse('${ApiEnv.baseUrl}$path');
    return qp.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...qp});
  }
}
