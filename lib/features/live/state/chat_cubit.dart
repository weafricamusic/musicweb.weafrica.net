import 'package:flutter/foundation.dart';

/// Simple notifier for sending comments from the UI.
class ChatCubit extends ValueNotifier<List<Map<String, dynamic>>> {
  ChatCubit() : super([]);

  void addComment(Map<String, dynamic> comment) {
    final updated = [...state, comment];
    if (updated.length > 50) updated.removeAt(0);
    value = updated;
  }

  void setComments(List<Map<String, dynamic>> comments) {
    value = comments;
  }
}
