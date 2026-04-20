// Web-only drag & drop bridge.

// ignore_for_file: deprecated_member_use

import 'dart:async';
// ignore: avoidweb_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';

import '_dropped_file.dart';

class WebDropTarget extends StatefulWidget {
  const WebDropTarget({
    super.key,
    required this.child,
    required this.onDrop,
    this.onHover,
    this.onTap,
  });

  final Widget child;
  final ValueChanged<DroppedFile> onDrop;
  final ValueChanged<bool>? onHover;
  final VoidCallback? onTap;

  @override
  State<WebDropTarget> createState() => _WebDropTargetState();
}

class _WebDropTargetState extends State<WebDropTarget> {
  late final String _viewType;
  html.DivElement? _element;

  StreamSubscription? _dragOverSub;
  StreamSubscription? _dragLeaveSub;
  StreamSubscription? _dropSub;
  StreamSubscription? _clickSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'weafrica-web-drop-${DateTime.now().microsecondsSinceEpoch}';

    _element = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'transparent'
      ..style.position = 'absolute'
      ..style.left = '0'
      ..style.top = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.zIndex = '10';

    _dragOverSub = _element!.onDragOver.listen((e) {
      e.preventDefault();
      widget.onHover?.call(true);
    });

    _dragLeaveSub = _element!.onDragLeave.listen((e) {
      e.preventDefault();
      widget.onHover?.call(false);
    });

    _dropSub = _element!.onDrop.listen((e) {
      e.preventDefault();
      widget.onHover?.call(false);

      final files = e.dataTransfer.files;
      if (files == null || files.isEmpty) return;
      final file = files.first;

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.first.then((_) {
        if (!mounted) return;
        final result = reader.result;
        if (result is! ByteBuffer) return;
        final bytes = Uint8List.view(result);
        widget.onDrop(
          DroppedFile(
            name: file.name,
            size: file.size,
            bytes: bytes,
            mimeType: file.type,
          ),
        );
      }).catchError((e) {
        // Prevent unhandled errors escaping from the DOM callback.
        debugPrint('⚠️ Web drop read failed: $e');
      });
    });

    _clickSub = _element!.onClick.listen((e) {
      e.preventDefault();
      widget.onTap?.call();
    });

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _element!);
  }

  @override
  void dispose() {
    _dragOverSub?.cancel();
    _dragLeaveSub?.cancel();
    _dropSub?.cancel();
    _clickSub?.cancel();
    _element = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: HtmlElementView(viewType: _viewType),
          ),
        ),
      ],
    );
  }
}
