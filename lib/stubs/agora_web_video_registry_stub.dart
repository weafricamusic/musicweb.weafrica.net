/// Stub for [AgoraWebVideoRegistry] on native (non-web) platforms.
///
/// Provides a no-op [register] and [getElement] so conditional imports
/// compile cleanly.  Native video rendering uses the Agora native SDK plugin.
class AgoraWebVideoRegistry {
  static String register(String key) => '';
  static Object? getElement(String key) => null;
  static void unregister(String key) {}
}