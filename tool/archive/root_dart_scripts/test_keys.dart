// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;

void main() async {
  final keys = [
    {
      'name': 'Key from earlier',
      'key': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzcyMzg5NjgsImV4cCI6MjA1MjgxNDk2OH0.oD1L8CK5Lz_OnvOb6fV5Hng2shY5QeF2bCjwyY-wF_o'
    },
    {
      'name': 'Key in tool/supabase.env.json',
      'key': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U'
    }
  ];
  
  const url = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  
  for (var keyInfo in keys) {
    print('Testing: ${keyInfo['name']}');
    print('Key: ${keyInfo['key']!.substring(0, 50)}...');
    
    try {
      // Test with a simple API call
      final response = await http.get(
        Uri.parse('$url/rest/v1/'),
        headers: {
          'apikey': keyInfo['key']!,
          'Authorization': 'Bearer ${keyInfo['key']!}',
        },
      );
      
      print('Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('✅ VALID KEY\n');
      } else {
        print('❌ INVALID KEY (Status: ${response.statusCode})\n');
      }
    } catch (e) {
      print('❌ ERROR: $e\n');
    }
  }
}
