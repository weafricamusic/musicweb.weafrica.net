// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔍 WEAFRICA IMAGE DIAGNOSTIC TOOL 🔍');
  print('=' * 50);
  
  // Your Supabase credentials
  const supabaseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
  const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzcyMzg5NjgsImV4cCI6MjA1MjgxNDk2OH0.oD1L8CK5Lz_OnvOb6fV5Hng2shY5QeF2bCjwyY-wF_o';
  
  print('\n1. 📡 Testing Network Connectivity...');
  try {
    final result = await InternetAddress.lookup('supabase.co');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
      print('✅ Internet connectivity: OK');
    }
  } catch (e) {
    print('❌ Internet connectivity: FAILED - $e');
  }
  
  print('\n2. 🔐 Testing Supabase Connection...');
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    print('✅ Supabase initialization: OK');
  } catch (e) {
    print('❌ Supabase initialization: FAILED - $e');
    return;
  }
  
  final supabase = Supabase.instance.client;
  
  print('\n3. 📦 Listing All Buckets...');
  try {
    final buckets = await supabase.storage.listBuckets();
    print('✅ Found ${buckets.length} buckets:');
    for (final bucket in buckets) {
      print('   • ${bucket.name} (Public: ${bucket.public})');
    }
  } catch (e) {
    print('❌ Failed to list buckets: $e');
  }
  
  print('\n4. 📁 Checking Specific Buckets for Files...');
  final bucketsToCheck = [
    'media',
    'song_thumbnails', 
    'artist-avatars',
    'video_thumbnails',
    'songs',
    'videos'
  ];
  
  for (final bucket in bucketsToCheck) {
    print('\n   📂 Bucket: $bucket');
    try {
      final files = await supabase.storage.from(bucket).list();
      print('   ✅ Found ${files.length} files');
      
      // Show first 3 files with their URLs
      for (final file in files.take(3)) {
        final url = '$supabaseUrl/storage/v1/object/public/$bucket/${file.name}';
        print('      📄 ${file.name}');
        print('      🔗 $url');
        
        // Test if URL is accessible
        try {
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          print('      📊 Status: ${response.statusCode} ${response.reasonPhrase}');
        } catch (e) {
          print('      ❌ URL test failed: $e');
        }
      }
      
      if (files.length > 3) {
        print('      ... and ${files.length - 3} more');
      }
    } catch (e) {
      print('   ❌ Error: $e');
    }
  }
  
  print('\n5. 🔍 Testing Sample Image URLs...');
  
  // Create a Flutter app to visually test images
  runApp(const ImageTestApp());
}

class ImageTestApp extends StatelessWidget {
  const ImageTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Image Test Results')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Test Images from Each Bucket',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              
              // Test images with direct URLs
              _buildTestImage(
                'media Bucket Test',
                'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/media/weafrica_logo.png',
              ),
              
              _buildTestImage(
                'artist-avatars Bucket Test',
                'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/artist-avatars/dj_spinall.jpg',
              ),
              
              _buildTestImage(
                'song_thumbnails Bucket Test',
                'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/song_thumbnails/default_cover.jpg',
              ),
              
              _buildTestImage(
                'Random Public Image (Control)',
                'https://picsum.photos/200/300',
              ),
              
              const SizedBox(height: 30),
              const Text(
                'Debug Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('If images above show broken:'),
                      const SizedBox(height: 10),
                      const Text('1. Check if files exist in buckets'),
                      const Text('2. Check bucket public permissions'),
                      const Text('3. Check RLS policies'),
                      const Text('4. Check CORS settings in Supabase'),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          // Open Supabase dashboard
                        },
                        child: const Text('Open Supabase Dashboard'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTestImage(String label, String url) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('URL: ${url.length > 50 ? '${url.substring(0, 50)}...' : url}'),
            const SizedBox(height: 10),
            Container(
              width: 200,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.network(
                url,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / 
                            loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  print('❌ Error loading $url: $error');
                  return Container(
                    color: Colors.red[50],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(height: 8),
                        Text(
                          error.toString().split(':').first,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
