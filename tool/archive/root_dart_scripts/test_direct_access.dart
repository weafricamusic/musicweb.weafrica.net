// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, prefer_interpolation_to_compose_strings

import 'dart:io';

void main() async {
  print('🔍 Testing direct file access');
  print('=' * 60);

  // Read from local environment (do NOT hardcode secrets into source control).
  // Example:
  //   SUPABASE_ANON_KEY=... dart run test_direct_access.dart
  final anonKey = Platform.environment['SUPABASE_ANON_KEY']?.trim() ?? '';
  
  // URLs that we know got 200 OK earlier
  final testUrls = [
    // Signed URL (worked)
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/song_thumbnails/hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    
    // Public URL with hyphen (worked)
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song-thumbnails/Onesimus.jpg',
    
    // Try different variations
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song_thumbnails/hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/song-thumbnails/Onesimus.jpg',
  ];
  
  for (var url in testUrls) {
    print('\n🔗 Testing: ${Uri.parse(url).path.split('/').last}');
    print('   URL: ${url.length > 80 ? '${url.substring(0, 80)}...' : url}');
    
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      
      // Add API key only if explicitly provided via env.
      if (anonKey.isNotEmpty) {
        request.headers.add('apikey', anonKey);
        request.headers.add('Authorization', 'Bearer $anonKey');
      }
      
      final response = await request.close();
      print('   Status: ${response.statusCode} ${response.reasonPhrase}');
      
      if (response.statusCode == 200) {
        print('   ✅ SUCCESS');
        
        // Check content type
        final contentType = response.headers.contentType;
        print('   Content-Type: $contentType');
        
        // Check content length
        final contentLength = response.contentLength;
        print('   Size: ${contentLength > 0 ? '${contentLength} bytes' : 'unknown'}');
      }
      
      client.close();
    } catch (e) {
      print('   ❌ Error: $e');
    }
  }
  
  // Also test a simple public image to ensure network works
  print('\n\n🌐 Testing network connectivity with public image:');
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('https://picsum.photos/200/300'));
    final response = await request.close();
    print('   Status: ${response.statusCode}');
    print('   ✅ Network is working');
    client.close();
  } catch (e) {
    print('   ❌ Network error: $e');
  }
}
