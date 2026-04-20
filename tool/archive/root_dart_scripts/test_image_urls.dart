// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings

import 'dart:io';

void main() async {
  print('🔍 Testing all image URLs from database\n');
  
  // All image URLs from your database
  final imageUrls = [
    // From songs table
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/song_thumbnails/hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song-thumbnails/Onesimus.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/thumbnails/me.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/song_thumbnails/RBm2W9YxiqctGs1aKBQphua9Ndj1/1767593981725_thumb_1767593980562_pita-peter-ft-dj-rio--invisible-crew-647a7ed0f1bf4.jpg',
    
    // From videos table
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/video_thumbnails/thumb_1767275029013_weafrica_music_icon_with_gold_accents_20260101_093427_0000.png',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/video_thumbnails/thumb_1767276225118_weafrica_music_icon_with_gold_accents_20260101_093427_0000.png',
  ];
  
  // Also test corrected versions
  final correctedUrls = [
    // Fix bucket name from song_thumbnails to song_thumbnails (signed to public)
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song_thumbnails/hxyIJoUqLbXfGydlKZ3pYnwGEAl1/1767530895282_thumb_1767530614276_screenshot_20251224_122602_google.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song_thumbnails/Onesimus.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song_thumbnails/me.jpg',
    'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song_thumbnails/RBm2W9YxiqctGs1aKBQphua9Ndj1/1767593981725_thumb_1767593980562_pita-peter-ft-dj-rio--invisible-crew-647a7ed0f1bf4.jpg',
  ];
  
  print('📋 ORIGINAL URLS:');
  print('=' * 60);
  
  for (var url in imageUrls) {
    print('\n🔗 Testing: ${url.split('/').last}');
    print('   Full URL: ${url.length > 80 ? url.substring(0, 80) + "..." : url}');
    
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      print('   📊 Status: ${response.statusCode} ${response.reasonPhrase}');
      
      if (response.statusCode == 200) {
        print('   ✅ SUCCESS: Image is accessible');
      } else if (response.statusCode == 404) {
        print('   ❌ FAIL: Image not found (404)');
      } else if (response.statusCode == 400 || response.statusCode == 403) {
        print('   ⚠️  ISSUE: Might be signed URL or permission problem');
      }
      
      client.close();
    } catch (e) {
      print('   ❌ ERROR: $e');
    }
  }
  
  print('\n\n📋 CORRECTED URLS:');
  print('=' * 60);
  
  for (var url in correctedUrls) {
    print('\n🔗 Testing: ${url.split('/').last}');
    print('   Full URL: ${url.length > 80 ? url.substring(0, 80) + "..." : url}');
    
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      print('   📊 Status: ${response.statusCode} ${response.reasonPhrase}');
      
      if (response.statusCode == 200) {
        print('   ✅ SUCCESS: Image is accessible');
      }
      
      client.close();
    } catch (e) {
      print('   ❌ ERROR: $e');
    }
  }
}
