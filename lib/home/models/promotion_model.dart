import 'package:flutter/material.dart';

class Promotion {
  final String id;
  final String title;
  final String description;
  final String badge;
  final IconData icon;
  final Gradient gradient;
  final Color accent;

  const Promotion({
    required this.id,
    required this.title,
    required this.description,
    required this.badge,
    required this.icon,
    required this.gradient,
    required this.accent,
  });
}
