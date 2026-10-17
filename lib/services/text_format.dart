/// Pure text helpers (no Flutter deps, unit-tested).
library;

const _trFold = {'ğ': 'g', 'ü': 'u', 'ş': 's', 'ö': 'o', 'ç': 'c', 'ı': 'i'};

/// Search key: Turkish-aware lower case without diacritics, so "ISIK", "Işık" and "isik" all
/// match. Dotted and dotless İ/I/ı/i all become i (Dart's `toLowerCase` keeps ı and is not
/// Turkish-aware), then ğüşöç lose their marks.
String foldTr(String text) => text
    .replaceAll('İ', 'i')
    .replaceAll('I', 'i')
    .toLowerCase()
    .replaceAllMapped(RegExp('[ğüşöçı]'), (m) => _trFold[m[0]]!);

/// Turkish upper case: i → İ, ı → I (Dart's `toUpperCase` turns i into I).
String upperTr(String text) => text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// 1536 → "1,5 KB" (binary units, tr-TR decimal comma; same output as the admin's formatBytes).
String formatBytes(num bytes, {int decimals = 1}) {
  if (!bytes.isFinite || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var i = 0;
  var value = bytes.toDouble();
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  var text = value.toStringAsFixed(i == 0 ? 0 : decimals);
  if (text.contains('.')) text = text.replaceFirst(RegExp(r'\.?0+$'), ''); // like maximumFractionDigits
  return '${text.replaceAll('.', ',')} ${units[i]}';
}

const _slugChars = {
  'ğ': 'g',
  'ü': 'u',
  'ş': 's',
  'ı': 'i',
  'ö': 'o',
  'ç': 'c',
  'Ğ': 'G',
  'Ü': 'U',
  'Ş': 'S',
  'İ': 'I',
  'Ö': 'O',
  'Ç': 'C',
};

/// Admin `generateSlug`: "Merhaba Dünya!" → "merhaba-dunya" (Turkish letters to ASCII, other symbols
/// dropped, spaces to single dashes; leading/trailing dashes removed so the slug pattern passes).
String slugify(String text) => text
    .split('')
    .map((c) => _slugChars[c] ?? c)
    .join()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Backend date (ISO string or epoch millis) → "13.10.2026 14:05" in local time (admin `tr-TR` short
/// date + time); unparseable → ''.
String formatDateTimeTr(Object? value) {
  final date = value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : DateTime.tryParse('$value');
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final d = date.toLocal();
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Bidi controls (U+061C, U+200E–200F, U+202A–202E, U+2066–2069) in untrusted text (RabbitMQ payloads, chat messages,
/// call peer names) could reorder what the admin reads ("Trojan Source"); they are shown as visible `⟨U+202E⟩` markers.
String revealBidi(String text) => text.replaceAllMapped(
  RegExp('[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'),
  (m) => '⟨U+${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0')}⟩',
);
