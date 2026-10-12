import 'package:elly_mobile_app/services/text_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('foldTr', () {
    test('dotted/dotless i in both cases fold to i', () {
      expect(foldTr('İ I ı i'), 'i i i i');
    });

    test('Turkish letters lose their diacritics, both cases', () {
      expect(foldTr('ĞÜŞÖÇ ğüşöç'), 'gusoc gusoc');
    });

    test('real words match each other however they are typed', () {
      for (final (a, b) in [('İSTANBUL', 'istanbul'), ('Işık', 'ISIK'), ('Çiçek', 'cicek'), ('ŞEHİR', 'şehir')]) {
        expect(foldTr(a), foldTr(b), reason: '$a ~ $b');
      }
    });

    test('İ folds to a single plain i', () => expect(foldTr('İ'), 'i'));

    test('other text is only lower-cased', () {
      expect(foldTr('Hello World 42'), 'hello world 42');
    });
  });

  group('upperTr', () {
    test('i → İ, ı → I', () => expect(upperTr('ilk ışık'), 'İLK IŞIK'));
    test('already upper / other letters', () => expect(upperTr('Öğe çay'), 'ÖĞE ÇAY'));
  });

  group('formatBytes (admin formatBytes parity)', () {
    for (final (bytes, text) in [
      (0, '0 B'),
      (-5, '0 B'),
      (512, '512 B'),
      (1024, '1 KB'),
      (1536, '1,5 KB'),
      (805306368, '768 MB'),
      (1073741824, '1 GB'),
      (1288490188, '1,2 GB'),
    ]) {
      test('$bytes → $text', () => expect(formatBytes(bytes), text));
    }
  });
}
