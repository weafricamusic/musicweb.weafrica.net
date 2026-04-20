import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirebaseSetupScreen extends StatelessWidget {
  final String? errorMessage;
  
  const FirebaseSetupScreen({
    super.key,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    // Skip Firebase check on web completely
    if (kIsWeb) {
      print('⚠️ Skipping Firebase setup on web');
      print('Error message would be: $errorMessage');
      return const SizedBox.shrink(); // Returns nothing
    }
    
    // Original UI for mobile
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64),
            const SizedBox(height: 16),
            const Text('App unavailable'),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
