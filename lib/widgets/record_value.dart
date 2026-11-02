import 'package:flutter/material.dart';
import '../core/format.dart';
import '../models/catalog.dart';
import '../models/record.dart';
import 'common.dart';

String recordValue(EntitySpec spec, Record record, String key) {
  final field = spec.fields.where((f) => f.key == key).firstOrNull;
  if (record.relation(key) != null) return record.relation(key)!.label;
  if (field?.kind == FieldKind.multiple) {
    return record.relations(key).map((r) => r.label).join(', ');
  }
  final value = record.text(key);
  if (value.isEmpty) return '—';
  if (field?.options.isNotEmpty == true) return field!.options[value] ?? value;
  if (field?.kind == FieldKind.dateTime ||
      ['created', 'updated'].contains(key)) {
    return dateLabel(value);
  }
  if (field?.kind == FieldKind.money ||
      ['total', 'labor_total', 'parts_total', 'unit_price'].contains(key)) {
    return money(record.number(key));
  }
  if (field?.kind == FieldKind.integer) {
    return record.number(key).toInt().toString();
  }
  return value;
}

Widget valueWidget(EntitySpec spec, Record record, String key) =>
    key == 'status' || key == 'condition'
        ? StatusBadge(record.text(key))
        : Text(
          recordValue(spec, record, key),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
