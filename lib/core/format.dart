import 'package:intl/intl.dart';
import '../models/catalog.dart';

final _money = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);
String money(num value) => _money.format(value);
String dateLabel(String value) {
  final date = DateTime.tryParse(value);
  return date == null
      ? '—'
      : DateFormat('dd.MM.yyyy · HH:mm').format(date.toLocal());
}

String inputDate(DateTime value) =>
    DateFormat('yyyy-MM-dd HH:mm').format(value);
String apiDate(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst('T', ' ');
double orderTotal(double labor, double parts, double discount) =>
    ((labor * (1 - discount / 100) + parts) * 100).round() / 100;
bool overlaps(DateTime a, DateTime b, DateTime c, DateTime d) =>
    a.isBefore(d) && b.isAfter(c);

String? validate(FieldSpec field, String? input, {bool editing = false}) {
  final value = input?.trim() ?? '';
  if (value.isEmpty) {
    return field.required && !(editing && field.kind == FieldKind.password)
        ? 'Обязательное поле'
        : null;
  }
  if (value.length > field.maxLength) {
    return 'Не больше ${field.maxLength} символов';
  }
  if (field.kind == FieldKind.email &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
    return 'Введите корректный email';
  }
  if (field.kind == FieldKind.phone &&
      !RegExp(r'^\+?[0-9 ()-]{10,20}$').hasMatch(value)) {
    return 'Введите телефон, например +7 (999) 123-45-67';
  }
  if (field.kind == FieldKind.password && value.length < 10) {
    return 'Минимум 10 символов';
  }
  if (field.key == 'vin' &&
      !RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(value.toUpperCase())) {
    return 'VIN: 17 букв и цифр, без I, O, Q';
  }
  if (field.key == 'plate' &&
      !RegExp(r'^[А-ЯA-Z0-9 -]{5,12}$').hasMatch(value.toUpperCase())) {
    return 'Проверьте госномер';
  }
  if (field.kind == FieldKind.integer || field.kind == FieldKind.money) {
    final number = double.tryParse(value.replaceAll(',', '.'));
    if (number == null ||
        !number.isFinite ||
        (field.kind == FieldKind.integer && number != number.roundToDouble())) {
      return 'Введите ${field.kind == FieldKind.integer ? 'целое число' : 'число'}';
    }
    if (field.min != null && number < field.min! ||
        field.max != null && number > field.max!) {
      return 'Допустимо: ${field.min?.toInt()}–${field.max?.toInt()}';
    }
    if (field.key == 'year' && number > DateTime.now().year + 1) {
      return 'Год выпуска не может быть в будущем';
    }
  }
  if (field.kind == FieldKind.dateTime &&
      DateTime.tryParse(value.replaceFirst(' ', 'T')) == null) {
    return 'Формат: ГГГГ-ММ-ДД ЧЧ:ММ';
  }
  return null;
}
