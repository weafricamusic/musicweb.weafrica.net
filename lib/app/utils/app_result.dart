// Artists/DJs NEVER see backend errors. Only beautiful UI states.

enum AppState { success, loading, error }

sealed class AppResult<T> {
  const AppResult();

  T? get data => switch (this) {
        AppSuccess<T>(:final data) => data,
        _ => null,
      };

  AppState toState() {
    return switch (this) {
      AppSuccess<T>() => AppState.success,
      AppFailure<T>() => AppState.error,
      AppLoading<T>() => AppState.loading,
    };
  }

  void when({
    required void Function(T data) success,
    required void Function() loading,
    required void Function() error,
  }) {
    switch (this) {
      case AppSuccess<T>(:final data):
        success(data);
      case AppLoading<T>():
        loading();
      case AppFailure<T>():
        error();
    }
  }
}

final class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.data);
  @override
  final T data;
}

final class AppLoading<T> extends AppResult<T> {
  const AppLoading();
}

final class AppFailure<T> extends AppResult<T> {
  const AppFailure({this.userMessage});

  /// Friendly, user-facing message (not raw backend errors).
  final String? userMessage;
}
