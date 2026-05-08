import 'package:flutter/material.dart';

class ViewerCountWidget extends StatelessWidget {
  final int count;
  const ViewerCountWidget({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.visibility, size: 14, color: Colors.blueAccent),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
