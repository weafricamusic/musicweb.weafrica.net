// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main() async {
  final apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U';
  final url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  
  print('📊 Checking database for image URLs\n');
  
  final tables = ['tracks', 'songs', 'videos'];
  
  for (final table in tables) {
    print('📋 Table: $table');
    print('─' * 40);
    
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('$url/rest/v1/$table?select=*&limit=5'),
      );
      
      request.headers.add('apikey', apiKey);
      request.headers.add('Authorization', 'Bearer $apiKey');
      request.headers.add('Prefer', 'return=representation');
      
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final items = json.decode(responseBody);
        
        if (items is List && items.isNotEmpty) {
          print('✅ Found ${items.length} records:');
          
          for (var item in items) {
            print('\n   📍 Record ID: ${item['id'] ?? 'N/A'}');
            print('   Title: ${item['title'] ?? 'N/A'}');
            
            // Look for image fields
            final imageFields = ['cover_url', 'thumbnail_url', 'image_url', 'artist_image_url', 'cover_image', 'thumbnail'];
            
            for (var field in imageFields) {
              if (item[field] != null) {
                print('   🖼️  $field: ${item[field]}');
                
                // Test if the image is accessible
                final imageUrl = item[field].toString();
                if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
                  // It's probably a storage path
                  final fullUrl = '$url/storage/v1/object/public/$imageUrl';
                  print('      🔗 Full URL: $fullUrl');
                  
                  // Test the URL
                  final testClient = HttpClient();
                  try {
                    final testRequest = await testClient.getUrl(Uri.parse(fullUrl));
                    final testResponse = await testRequest.close();
                    print('      📊 Status: ${testResponse.statusCode}');
                  } catch (e) {
                    print('      ❌ Error: $e');
                  }
                  testClient.close();
                }
              }
            }
          }
        } else {
          print('ℹ️  No records found in this table');
        }
      } else {
        print('❌ Failed to query table (Status: ${response.statusCode})');
      }
      
      client.close();
    } catch (e) {
      print('❌ Error: $e');
    }
    
    print('');
  }
}
