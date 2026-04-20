// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main() async {
  final apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U';
  final url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  
  print('🔍 Checking ACTUAL files in buckets\n');
  
  final buckets = [
    'song_thumbnails',
    'video_thumbnails',
    'thumbnails',
    'artist-avatars',
    'media'
  ];
  
  for (final bucket in buckets) {
    print('📂 Bucket: $bucket');
    print('─' * 40);
    
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('$url/storage/v1/object/list/$bucket'),
      );
      
      request.headers.add('apikey', apiKey);
      request.headers.add('Authorization', 'Bearer $apiKey');
      request.headers.add('Content-Type', 'application/json');
      request.write(json.encode({'limit': 100}));
      
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final files = json.decode(responseBody);
        
        if (files is List && files.isNotEmpty) {
          print('✅ Found ${files.length} files:');
          for (var file in files.take(10)) {
            final name = file['name'];
            print('   • $name');
          }
          if (files.length > 10) {
            print('   ... and ${files.length - 10} more');
          }
        } else {
          print('ℹ️  No files found in this bucket');
        }
      } else if (response.statusCode == 404) {
        print('❌ Bucket does not exist (404)');
      } else {
        print('⚠️  Unexpected status: ${response.statusCode}');
      }
      
      client.close();
    } catch (e) {
      print('❌ Error: $e');
    }
    
    print('');
  }
}
