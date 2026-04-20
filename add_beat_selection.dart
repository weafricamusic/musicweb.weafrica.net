import 'dart:io';

void main() {
  final file = File('lib/features/live/screens/go_live_setup_screen.dart');
  var content = file.readAsStringSync();
  
  // Find the battle details row and add beat selection after it
  final battleDetailsIndex = content.indexOf('_buildGlassPill(');
  if (battleDetailsIndex != -1) {
    // Find where to insert after the battle details
    final insertAfter = 'const SizedBox(height: 16),';
    final insertPos = content.indexOf(insertAfter, battleDetailsIndex);
    
    if (insertPos != -1) {
      final beatWidget = '''
          const SizedBox(height: 16),
          if (_battleModeEnabled)
            BeatSelectionWidget(
              onBeatSelected: (beat) {
                setState(() {
                  _selectedBeatId = beat?.id;
                });
                if (beat != null) {
                  _debugLog('🎵 Beat selected: \${beat.name}');
                }
              },
              initialBeatId: _selectedBeatId,
            ),
''';
      content = content.replaceFirst(insertAfter, '$insertAfter$beatWidget');
      file.writeAsStringSync(content);
      print('✅ Beat selection added to GoLiveSetupScreen');
    } else {
      print('❌ Could not find insertion point');
    }
  } else {
    print('❌ Could not find battle details section');
  }
}
