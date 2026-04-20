#!/usr/bin/env dart

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';

// Simple script to upload an ad audio file
// Usage: dart upload_ad.dart <audio_file_path> <title>

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart upload_ad.dart <audio_file_path> <title>');
    exit(1);
  }

  final audioFilePath = args[0];
  final title = args[1];

  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Sign in (you'll need to handle auth)
  // For now, assume user is signed in via Firebase CLI or something
  
  final file = File(audioFilePath);
  if (!file.existsSync()) {
    print('File does not exist: $audioFilePath');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  
  // Upload to storage
  final storageUri = Uri.parse('https://your-supabase-url.supabase.co/api/uploads/storage');
  final request = http.MultipartRequest('POST', storageUri)
    ..fields['bucket'] = 'ads'
    ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: title));
  
  final response = await request.send();
  final responseBody = await response.stream.bytesToString();
  
  if (response.statusCode != 200) {
    print('Upload failed: ${response.statusCode} $responseBody');
    exit(1);
  }
  
  final uploadResult = jsonDecode(responseBody);
  final audioUrl = uploadResult['public_url'] ?? uploadResult['signed_url'];
  
  // Create ad record
  final adUri = Uri.parse('https://your-supabase-url.supabase.co/api/ads/create');
  final adResponse = await http.post(
    adUri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'title': title,
      'audio_url': audioUrl,
    }),
  );
  
  if (adResponse.statusCode == 200) {
    print('Ad uploaded successfully!');
  } else {
    print('Failed to create ad: ${adResponse.statusCode} ${adResponse.body}');
  }
}