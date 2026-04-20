import 'package:web/web.dart' as web;

void warmupWebConnections(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;

  final origin = uri.origin;
  final head = web.document.head;
  if (head == null) return;

  void addLink(String rel) {
    final selector = 'link[rel="$rel"][href="$origin"]';
    if (head.querySelector(selector) != null) return;

    final link = web.HTMLLinkElement()
      ..rel = rel
      ..href = origin;

    if (rel == 'preconnect') {
      link.crossOrigin = 'anonymous';
    }

    head.append(link);
  }

  addLink('dns-prefetch');
  addLink('preconnect');
}
