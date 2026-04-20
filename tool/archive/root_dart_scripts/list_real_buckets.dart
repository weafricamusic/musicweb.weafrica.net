// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main() async {
  final apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U';
  final url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  
  print('🔍 Listing ALL buckets in your project\n');
  
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$url/storage/v1/bucket'));
    
    request.headers.add('apikey', apiKey);
    request.headers.add('Authorization', 'Bearer $apiKey');
    
    final response = await request.close();
    
    if (response.statusCode == 200) {
      final responseBody = await response.transform(utf8.decoder).join();
      final buckets = json.decode(responseBody);
      
      if (buckets is List && buckets.isNotEmpty) {
        print('✅ Found ${buckets.length} buckets:');
        for (var bucket in buckets) {
          final name = bucket['name'];
          final public = bucket['public'] ?? false;
          final id = bucket['id'];
          print('   📂 $name');
          print('      ID: $id');
          print('      Public: $public');
          print('');
        }
      } else {
        print('ℹ️  No buckets found');
      }
    } else {
      print('❌ Failed to list buckets (Status: ${response.statusCode})');
      print('   Response headers:');
      response.headers.forEach((name, values) {
        print('   $name: $values');
      });
    }
    
    client.close();
  } catch (e) {
    print('❌ Error: $e');
  }
}
