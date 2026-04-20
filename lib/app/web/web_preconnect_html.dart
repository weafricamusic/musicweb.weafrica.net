import 'package:web/web.dart' as web;

void warmupWebConnections(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;

  final origin = uri.origin;
  final head = web.document.head;
  if (head == null) return;

  bool exists(String rel) {
    return head.querySelector('link[rel="$rel"][href^="$origin"]') != null;
  }

  void addLink(String rel, {bool crossOrigin = false}) {
    if (exists(rel)) return;

    final link = web.HTMLLinkElement()
      ..rel = rel
      ..href = origin;

    if (crossOrigin) {
      link.crossOrigin = 'anonymous';
    }

    head.append(link);
  }

  addLink('dns-prefetch');
  addLink('preconnect', crossOrigin: true);
}