import 'package:dharma_library/core/translit/translit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Devanagari → IAST', () {
    test('SB 1.1.1 opening', () {
      expect(Translit.devaToIast('जन्माद्यस्य यतोऽन्वयादितरतश्चार्थेष्वभिज्ञः स्वराट्'),
          "janmādyasya yato'nvayāditarataścārtheṣvabhijñaḥ svarāṭ");
    });
    test('oṁ, anusvāra, visarga, daṇḍa, digits', () {
      expect(Translit.devaToIast('ॐ नमो भगवते वासुदेवाय ॥ १ ॥'), 'oṁ namo bhagavate vāsudevāya || 1 ||');
      expect(Translit.devaToIast('ऋषयः'), 'ṛṣayaḥ');
      expect(Translit.devaToIast('कृष्णः'), 'kṛṣṇaḥ');
    });
  });

  group('Devanagari → Indic scripts', () {
    const src = 'धाम्ना स्वेन सदा निरस्तकुहकं सत्यं परं धीमहि ॥ १ ॥';
    test('Malayalam with chillu', () {
      expect(Translit.devaToScript('निरस्तकुहकं सत्यं परं', 'Mlym'), 'നിരസ്തകുഹകം സത്യം പരം');
      expect(Translit.devaToScript('त्रिसर्गोऽमृषा', 'Mlym'), 'ത്രിസർഗോഽമൃഷാ');
      expect(Translit.devaToScript('ऋषय ऊचुः', 'Mlym'), 'ഋഷയ ഊചുഃ');
    });
    test('Kannada / Telugu / Bengali / Gujarati round-trip shape', () {
      expect(Translit.devaToScript(src, 'Knda'), 'ಧಾಮ್ನಾ ಸ್ವೇನ ಸದಾ ನಿರಸ್ತಕುಹಕಂ ಸತ್ಯಂ ಪರಂ ಧೀಮಹಿ ॥ ೧ ॥');
      expect(Translit.devaToScript(src, 'Telu'), 'ధామ్నా స్వేన సదా నిరస్తకుహకం సత్యం పరం ధీమహి ॥ ౧ ॥');
      expect(Translit.devaToScript('वासुदेवाय', 'Beng'), 'বাসুদেবায');
      expect(Translit.devaToScript('ॐ', 'Gujr'), 'ૐ');
    });
    test('Tamil is lossy but stable', () {
      expect(Translit.isLossy('Taml'), isTrue);
      expect(Translit.devaToScript('भगवते', 'Taml'), 'பகவதே');
    });
    test('identity for Deva and IAST for Latn', () {
      expect(Translit.devaToScript(src, 'Deva'), src);
      expect(Translit.devaToScript('कृष्ण', 'Latn'), 'kṛṣṇa');
    });
  });
}
