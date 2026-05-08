import 'package:flutter/material.dart';
import '../models/live_args.dart';

class LiveScreen extends StatelessWidget {
  final LiveArgs? args;

  const LiveScreen({super.key, this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live (stub)')),
      body: const Center(child: Text('Live screen (stub)')),
    );
  }
}
