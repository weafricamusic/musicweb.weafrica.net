import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Bridges Flutter's [HtmlElementView] with Agora Web SDK track playback.
///
/// Call [register] once per video view to create the backing [DivElement]
/// and register it with Flutter's platform view registry.
/// The returned [viewType] string is used as the `viewType` for [HtmlElementView].
///
/// AgoraService calls [getElement] to retrieve the div and play a track into it.
class AgoraWebVideoRegistry {
  static final Map<String, html.DivElement> _elements = {};

  /// Creates a [DivElement], registers it as a platform view, and returns the
  /// `viewType` string to use in [HtmlElementView].
  ///
  /// [key] is a stable identifier, e.g. `'local'` or `'remote-12345'`.
  static String register(String key) {
    final viewType = 'agora-video-$key';

    if (_elements.containsKey(viewType)) {
      return viewType; // already registered
    }

    final div = html.DivElement()
      ..id = viewType
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';

    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) => div);

    _elements[viewType] = div;
    return viewType;
  }

  /// Returns the [DivElement] backing a previously registered view.
  static html.DivElement? getElement(String key) {
    final viewType = 'agora-video-$key';
    return _elements[viewType];
  }

  /// Removes the registration (does not remove the element from the DOM —
  /// Flutter handles that when the widget is unmounted).
  static void unregister(String key) {
    final viewType = 'agora-video-$key';
    _elements.remove(viewType);
  }
}