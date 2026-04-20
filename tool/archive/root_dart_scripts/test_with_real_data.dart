// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main() async {
  print('🧪 Testing with real database data');
  print('=' * 60);
  
  final apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U';
  final url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  
  // Get some songs with images
  try {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('$url/rest/v1/songs?select=title,thumbnail_url&limit=5'),
    );
    
    request.headers.add('apikey', apiKey);
    request.headers.add('Authorization', 'Bearer $apiKey');
    
    final response = await request.close();
    
    if (response.statusCode == 200) {
      final responseBody = await response.transform(utf8.decoder).join();
      final songs = json.decode(responseBody);
      
      print('🎵 Found ${songs.length} songs with image data:\n');
      
      for (var song in songs) {
        final title = song['title'] ?? 'No title';
        final thumbnailUrl = song['thumbnail_url']?.toString() ?? '';
        
        print('📀 "$title"');
        print('   Thumbnail URL: $thumbnailUrl');
        
        if (thumbnailUrl.isNotEmpty) {
          // Test if the URL is accessible
          try {
            final testClient = HttpClient();
            final testRequest = await testClient.getUrl(Uri.parse(thumbnailUrl));
            final testResponse = await testRequest.close();
            print('   Status: ${testResponse.statusCode}');
            
            if (testResponse.statusCode == 200) {
              print('   ✅ ACCESSIBLE');
            } else {
              print('   ❌ NOT ACCESSIBLE (Status: ${testResponse.statusCode})');
            }
            
            testClient.close();
          } catch (e) {
            print('   ❌ ERROR: $e');
          }
        } else {
          print('   ℹ️  No thumbnail URL');
        }
        
        print('');
      }
    } else {
      print('❌ Failed to fetch songs: ${response.statusCode}');
    }
    
    client.close();
  } catch (e) {
    print('❌ Error: $e');
  }
  
  print('\n🔍 Testing URL conversion logic:');
  print('=' * 60);
  
  final testCases = [
    'hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    'storage/v1/object/song_thumbnails/hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/song_thumbnails/hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    'Onesimus.jpg',
    '',
  ];
  
  for (var testCase in testCases) {
    final converted = _convertUrl(testCase);
    print('\nInput: "$testCase"');
    print('Output: "$converted"');
    
    if (testCase.isNotEmpty && testCase != converted) {
      // Test the converted URL
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(converted));
        final response = await request.close();
        print('Status: ${response.statusCode}');
        client.close();
      } catch (e) {
        print('Error: $e');
      }
    }
  }
}

String _convertUrl(String input) {
  if (input.isEmpty) return '';
  
  var path = input.trim();
  
  if (path.startsWith('http')) {
    return path;
  }
  
  if (path.contains('storage/v1/object/')) {
    const baseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
    if (path.startsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }
  
  const baseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  
  if (path.startsWith('/')) {
    path = path.substring(1);
  }

  // Bare filename (no folders) lives in the public `song-thumbnails` bucket.
  // Example: `Onesimus.jpg`
  if (!path.contains('/')) {
    return '$baseUrl/storage/v1/object/public/song-thumbnails/${Uri.encodeComponent(path)}';
  }

  // If the input already includes a known bucket prefix, treat it as a public object path.
  // Example: `song-thumbnails/Onesimus.jpg`
  final lower = path.toLowerCase();
  if (lower.startsWith('song-thumbnails/') ||
      lower.startsWith('song_thumbnails/') ||
      lower.startsWith('songs/') ||
      lower.startsWith('media/') ||
      lower.startsWith('thumbnails/')) {
    final encoded = path
        .split('/')
        .map((s) => Uri.encodeComponent(s))
        .join('/');
    return '$baseUrl/storage/v1/object/public/$encoded';
  }

  final encodedPath = path
      .split('/')
      .map((s) => Uri.encodeComponent(s))
      .join('/');
  
  // Folder paths from the DB commonly point at the (non-public) `song_thumbnails` endpoint.
  return '$baseUrl/storage/v1/object/song_thumbnails/$encodedPath';
}
