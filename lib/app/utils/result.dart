/// Minimal Result type to avoid throwing for expected failures.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get data => switch (this) {
        Success<T>(:final data) => data,
        Failure<T>() => null,
      };

  Exception? get error => switch (this) {
        Success<T>() => null,
        Failure<T>(:final error) => error,
      };

  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(Exception error) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final data) => onSuccess(data),
      Failure<T>(:final error) => onFailure(error),
    };
  }

  static Result<T> success<T>(T data) => Success<T>(data);
  static Result<T> failure<T>(Exception error) => Failure<T>(error);
}

final class Success<T> extends Result<T> {
  const Success(this.data);
  @override
  final T data;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error);
  @override
  final Exception error;
}
