import 'package:dharma_library/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('launch sound defaults off; cues are preference-gated and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final s = Settings.load(p);
    expect(s.launchSound, isFalse);
    expect(s.devotionalSounds, isTrue);
    expect(s.slokaAudioCues, isTrue);

    final next = s.copyWith(launchSound: true, slokaAudioCues: false, soundVolume: 0.2);
    await next.save(p);
    final reloaded = Settings.load(p);
    expect(reloaded.launchSound, isTrue);
    expect(reloaded.slokaAudioCues, isFalse);
    expect(reloaded.soundVolume, closeTo(0.2, 0.001));
  });
}
