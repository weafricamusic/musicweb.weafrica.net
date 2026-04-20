import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../../app/services/connectivity_service.dart';
import '../../../app/utils/retry_utils.dart';
import '../models/ai_monetization_models.dart';

enum ApiErrorType {
  network,
  timeout,
  authentication,
  server,
  client,
  parse,
  unknown,
}

extension ApiErrorTypeX on ApiErrorType {
  bool get isRetryable => this == ApiErrorType.network || this == ApiErrorType.timeout || this == ApiErrorType.server;
}

class ApiException implements Exception {
  ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.originalError,
    bool? canRetry,
  }) : canRetry = canRetry ?? type.isRetryable;

  final ApiErrorType type;
  final String message;
  final int? statusCode;
  final Object? originalError;
  final bool canRetry;

  @override
  String toString() => 'ApiException[$type]: $message';
}

class ApiResponse<T> {
  const ApiResponse.success(this.data)
      : success = true,
        error = null;

  const ApiResponse.failure(this.error)
      : success = false,
        data = null;

  final bool success;
  final T? data;
  final ApiException? error;
}

class AiMonetizationApi {
  AiMonetizationApi({
    ApiUriBuilder? uriBuilder,
    ConnectivityService? connectivityService,
    http.Client? httpClient,
  })  : _uriBuilder = uriBuilder ?? const ApiUriBuilder(),
        _connectivity = connectivityService ?? ConnectivityService.instance,
        _http = httpClient ?? http.Client();

  final ApiUriBuilder _uriBuilder;
  final ConnectivityService _connectivity;
  final http.Client _http;

  final Map<String, _CachedEntry> _cache = <String, _CachedEntry>{};
  static const Duration cacheDuration = Duration(minutes: 5);

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    return _uriBuilder.build(path, queryParameters: queryParameters);
  }

  Future<http.Response> _executeRequest({
    required String operation,
    required Future<http.Response> Function() request,
    bool checkConnectivity = true,
  }) async {
    if (checkConnectivity) {
      final hasConnection = await _connectivity.hasConnection;
      if (!hasConnection) {
        throw ApiException(
          type: ApiErrorType.network,
          message: 'No internet connection',
        );
      }
    }

    return RetryUtils.withRetry<http.Response>(
      operation: operation,
      maxRetries: 3,
      initialDelay: const Duration(seconds: 1),
      shouldRetry: (error) {
        if (error is ApiException) return error.canRetry;
        if (error is SocketException) return true;
        if (error is TimeoutException) return true;
        return false;
      },
      action: () async {
        try {
          final response = await request().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Request timed out'),
          );

          developer.log(
            '$operation completed (${response.statusCode})',
            name: 'WEAFRICA.Api',
          );

          if (response.statusCode == 401 || response.statusCode == 403) {
            throw ApiException(
              type: ApiErrorType.authentication,
              message: 'Authentication failed',
              statusCode: response.statusCode,
              canRetry: false,
            );
          }

          if (response.statusCode >= 500) {
            throw ApiException(
              type: ApiErrorType.server,
              message: 'Server error',
              statusCode: response.statusCode,
            );
          }

          return response;
        } on SocketException catch (e) {
          throw ApiException(
            type: ApiErrorType.network,
            message: 'Network error: ${e.message}',
            originalError: e,
          );
        } on TimeoutException catch (e) {
          throw ApiException(
            type: ApiErrorType.timeout,
            message: 'Request timeout',
            originalError: e,
          );
        }
      },
    );
  }

  Future<ApiResponse<AiBalanceResponse>> balance({bool forceRefresh = false}) async {
    const cacheKey = 'ai_balance';

    final cached = _cache[cacheKey];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      developer.log('Using cached AI balance', name: 'WEAFRICA.Api');
      return ApiResponse.success(cached.data as AiBalanceResponse);
    }

    final uri = _buildUri('/api/ai/balance');

    try {
      final response = await _executeRequest(
        operation: 'AI Balance',
        request: () => FirebaseAuthedHttp.get(
          uri,
          headers: const {'Accept': 'application/json'},
          timeout: const Duration(seconds: 10),
          requireAuth: true,
        ),
      );

      final body = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResponse.failure(_httpError(response.statusCode, body));
      }

      final map = _asJsonMap(body);
      final data = AiBalanceResponse.fromJson(map);

      _cache[cacheKey] = _CachedEntry(data: data, timestamp: DateTime.now());
      return ApiResponse.success(data);
    } on ApiException catch (e, st) {
      developer.log('Balance failed: ${e.message}', name: 'WEAFRICA.Api', error: e, stackTrace: st);
      return ApiResponse.failure(e);
    } catch (e, st) {
      developer.log('Balance failed (unknown)', name: 'WEAFRICA.Api', error: e, stackTrace: st);
      return ApiResponse.failure(ApiException(type: ApiErrorType.unknown, message: e.toString(), originalError: e));
    }
  }

  Future<ApiResponse<List<AiPricingItem>>> pricing({bool forceRefresh = false}) async {
    const cacheKey = 'ai_pricing';

    final cached = _cache[cacheKey];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      developer.log('Using cached AI pricing', name: 'WEAFRICA.Api');
      return ApiResponse.success((cached.data as List).cast<AiPricingItem>());
    }

    final uri = _buildUri('/api/ai/pricing');

    try {
      final response = await _executeRequest(
        operation: 'AI Pricing',
        request: () => _http.get(uri, headers: const {'Accept': 'application/json'}),
      );

      final body = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResponse.failure(_httpError(response.statusCode, body));
      }

      final map = _asJsonMap(body);
      final listAny = map['pricing'];
      final list = listAny is List ? listAny : const <dynamic>[];

      final items = <AiPricingItem>[];
      for (final entry in list) {
        if (entry is Map) {
          final m = entry.map((k, v) => MapEntry(k.toString(), v));
          items.add(AiPricingItem.fromJson(m));
        }
      }

      _cache[cacheKey] = _CachedEntry(data: items, timestamp: DateTime.now());
      return ApiResponse.success(items);
    } on ApiException catch (e, st) {
      developer.log('Pricing failed: ${e.message}', name: 'WEAFRICA.Api', error: e, stackTrace: st);
      return ApiResponse.failure(e);
    } catch (e, st) {
      developer.log('Pricing failed (unknown)', name: 'WEAFRICA.Api', error: e, stackTrace: st);
      return ApiResponse.failure(ApiException(type: ApiErrorType.unknown, message: e.toString(), originalError: e));
    }
  }

  void clearCache() {
    _cache.clear();
    developer.log('AI monetization API cache cleared', name: 'WEAFRICA.Api');
  }
}

class _CachedEntry {
  const _CachedEntry({
    required this.data,
    required this.timestamp,
  });

  final Object data;
  final DateTime timestamp;

  bool get isExpired => DateTime.now().difference(timestamp) > AiMonetizationApi.cacheDuration;
}

dynamic _decodeJson(String body) {
  try {
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _asJsonMap(dynamic decoded) {
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
  return const <String, dynamic>{};
}

ApiException _httpError(int statusCode, dynamic decoded) {
  final map = _asJsonMap(decoded);
  final msg = (map['message'] ?? map['error'] ?? map['description'] ?? decoded ?? 'Unknown error').toString();

  if (statusCode == 401 || statusCode == 403) {
    return ApiException(type: ApiErrorType.authentication, message: msg, statusCode: statusCode, canRetry: false);
  }
  if (statusCode >= 500) {
    return ApiException(type: ApiErrorType.server, message: msg, statusCode: statusCode);
  }
  if (statusCode >= 400) {
    return ApiException(type: ApiErrorType.client, message: msg, statusCode: statusCode, canRetry: false);
  }
  return ApiException(type: ApiErrorType.unknown, message: msg, statusCode: statusCode, canRetry: false);
}
