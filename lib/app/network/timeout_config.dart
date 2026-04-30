import 'package:http/http.dart' as http;

class TimeoutConfig {
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration readTimeout = Duration(seconds: 30);
  
  static Future<http.Response> getWithTimeout(String url) async {
    return http.get(Uri.parse(url)).timeout(connectTimeout);
  }
  
  static Future<http.Response> postWithTimeout(String url, {dynamic body}) async {
    return http.post(Uri.parse(url), body: body).timeout(connectTimeout);
  }
}
