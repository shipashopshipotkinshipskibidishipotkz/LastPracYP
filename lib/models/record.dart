class Record {
  final Map<String, dynamic> data;
  const Record(this.data);
  String get id => text('id');
  String text(String key) => data[key]?.toString() ?? '';
  double number(String key) => (data[key] as num?)?.toDouble() ?? 0;
  bool get archived => text('deleted_at').isNotEmpty;
  List<String> ids(String key) =>
      (data[key] as List? ?? []).map((e) => '$e').toList();
  Record? relation(String key) {
    final value = (data['expand'] as Map?)?[key];
    return value is Map ? Record(Map<String, dynamic>.from(value)) : null;
  }

  List<Record> relations(String key) =>
      ((data['expand'] as Map?)?[key] as List? ?? [])
          .map((e) => Record(Map<String, dynamic>.from(e as Map)))
          .toList();
  String get label {
    if (text('number').isNotEmpty) return text('number');
    if (text('plate').isNotEmpty) {
      return '${text('brand')} ${text('model')} · ${text('plate')}';
    }
    if (text('name').isNotEmpty) return text('name');
    return relation('order')?.label ??
        relation('user')?.label ??
        relation('part')?.label ??
        id;
  }
}

class RecordPage {
  final List<Record> items;
  final int page, totalItems, totalPages;
  const RecordPage(this.items, this.page, this.totalItems, this.totalPages);
  factory RecordPage.fromJson(Map<String, dynamic> json) => RecordPage(
    (json['items'] as List)
        .map((e) => Record(Map<String, dynamic>.from(e)))
        .toList(),
    json['page'] as int,
    json['totalItems'] as int,
    json['totalPages'] as int,
  );
}

enum Role {
  admin('Администратор'),
  master('Мастер'),
  client('Клиент');

  final String title;
  const Role(this.title);
  static Role parse(String value) =>
      Role.values.firstWhere((e) => e.name == value, orElse: () => Role.client);
}
