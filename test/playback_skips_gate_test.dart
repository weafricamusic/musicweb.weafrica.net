import 'package:flutter_test/flutter_test.dart';

import 'package:weafrica_music/services/playback_skips_gate.dart';

void main() {
  test('PlaybackSkipsGate warns near limit and blocks at limit', () async {
    var now = DateTime(2025, 1, 1, 0, 0, 0);
    final events = <SkipGateEvent>[];

    final gate = PlaybackSkipsGate(
      maxSkipsPerHourProvider: () => 3,
      now: () => now,
    );

    final sub = gate.events.listen(events.add);

    // 1st skip: remaining=2 -> warning (near limit threshold is 2).
    expect(gate.tryConsumeUserSkip(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(events.where((e) => e.type == SkipGateEventType.warning).length, 1);

    // 2nd skip: remaining=1 -> warning would normally fire, but cooldown prevents spamming.
    now = now.add(const Duration(minutes: 1));
    expect(gate.tryConsumeUserSkip(), isTrue);

    // 3rd skip: remaining=0 -> allowed (limit reached after consuming).
    now = now.add(const Duration(minutes: 1));
    expect(gate.tryConsumeUserSkip(), isTrue);

    // 4th skip within the hour: blocked.
    now = now.add(const Duration(minutes: 1));
    expect(gate.tryConsumeUserSkip(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(events.any((e) => e.type == SkipGateEventType.blocked), isTrue);

    await sub.cancel();
    await gate.dispose();
  });

  test('PlaybackSkipsGate resets after window passes', () {
    var now = DateTime(2025, 1, 1, 0, 0, 0);

    final gate = PlaybackSkipsGate(
      maxSkipsPerHourProvider: () => 2,
      now: () => now,
    );

    expect(gate.tryConsumeUserSkip(), isTrue);
    now = now.add(const Duration(minutes: 1));
    expect(gate.tryConsumeUserSkip(), isTrue);

    // Next would be blocked within the hour.
    now = now.add(const Duration(minutes: 1));
    expect(gate.tryConsumeUserSkip(), isFalse);

    // Advance beyond the 1h window.
    now = now.add(const Duration(hours: 1, minutes: 1));
    expect(gate.tryConsumeUserSkip(), isTrue);

    gate.dispose();
  });
}
