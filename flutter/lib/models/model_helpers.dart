import 'package:intl/intl.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

String dateKey(DateTime value) => _dateFormat.format(value);

DateTime startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

List<Map<String, dynamic>> rows(dynamic data) {
  if (data == null) return [];
  return (data as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

Map<String, dynamic>? maybeRow(dynamic data) {
  if (data == null) return null;
  return Map<String, dynamic>.from(data as Map);
}

int intValue(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ?? fallback;
}

double doubleValue(Object? value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

String compactDate(Object? value) {
  if (value == null) return 'No date';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return value.toString();
  return DateFormat('MMM d').format(date);
}
