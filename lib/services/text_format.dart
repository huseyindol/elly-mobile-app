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
