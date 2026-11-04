import 'package:intl/intl.dart';

/// Backend timestamps must have an explicit UTC timezone. SQLite sometimes
/// returns naive timestamps, so we interpret those legacy values as UTC.
String formatIndiaTime(dynamic raw) {
  if (raw == null) return '';
  try {
    final text = raw.toString().trim();
    final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text);
    final parsed = DateTime.parse(zoned ? text : '${text}Z').toUtc();
    final ist = parsed.add(const Duration(hours: 5, minutes: 30));
    return '${DateFormat('d MMM, h:mm a').format(ist)} IST';
  } catch (_) { return raw.toString(); }
}
