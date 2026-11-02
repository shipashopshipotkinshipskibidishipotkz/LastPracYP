import 'package:flutter_test/flutter_test.dart';
import 'package:autoservice_web/app.dart';
import 'package:autoservice_web/core/format.dart';
import 'package:autoservice_web/models/catalog.dart';
import 'package:autoservice_web/models/record.dart';
import 'package:autoservice_web/repositories/repository.dart';

void main() {
  test('labor discount never reduces the price of parts', () {
    expect(orderTotal(6500, 4750, 10), 10600);
    expect(orderTotal(1999.99, 850, 15), 2549.99);
    expect(orderTotal(0, 850, 30), 850);
  });
  test('adjacent workshop slots do not overlap', () {
    final start = DateTime(2026, 11, 2, 9);
    expect(
      overlaps(
        start,
        start.add(const Duration(hours: 1)),
        start.add(const Duration(hours: 1)),
        start.add(const Duration(hours: 2)),
      ),
      false,
    );
    expect(
      overlaps(
        start,
        start.add(const Duration(hours: 1)),
        start.add(const Duration(minutes: 30)),
        start.add(const Duration(hours: 2)),
      ),
      true,
    );
  });
  test('VIN accepts 17 characters and rejects I O Q', () {
    final vin = entity('vehicles').fields.firstWhere((f) => f.key == 'vin');
    expect(validate(vin, 'JTNB11HK003012345'), isNull);
    expect(validate(vin, 'JTNB11IK003012345'), isNotNull);
    expect(validate(vin, '123'), isNotNull);
  });
  test('year and mileage enforce real ranges', () {
    final fields = entity('vehicles').fields;
    final year = fields.firstWhere((f) => f.key == 'year');
    final mileage = fields.firstWhere((f) => f.key == 'mileage');
    expect(validate(year, '1949'), isNotNull);
    expect(validate(year, '${DateTime.now().year + 2}'), isNotNull);
    expect(validate(year, '2020'), isNull);
    expect(validate(mileage, '-1'), isNotNull);
    expect(validate(mileage, '1.5'), isNotNull);
  });
  test('required input and maximum lengths are checked', () {
    const field = FieldSpec('name', 'Название', maxLength: 5);
    expect(validate(field, '  '), isNotNull);
    expect(validate(field, '123456'), isNotNull);
    expect(validate(field, 'Гайка'), isNull);
  });
  test('phone and email formats are validated', () {
    const phone = FieldSpec(
      'phone',
      'Телефон',
      kind: FieldKind.phone,
      maxLength: 20,
    );
    const email = FieldSpec('email', 'Email', kind: FieldKind.email);
    expect(validate(phone, '+7 (999) 123-45-67'), isNull);
    expect(validate(phone, 'abc'), isNotNull);
    expect(validate(email, 'mail@example.com'), isNull);
    expect(validate(email, 'mail@'), isNotNull);
  });
  test('optional edit password can be empty, registration cannot', () {
    const field = FieldSpec('password', 'Пароль', kind: FieldKind.password);
    expect(validate(field, '', editing: true), isNull);
    expect(validate(field, ''), isNotNull);
    expect(validate(field, 'short'), isNotNull);
  });
  test('numbers reject NaN and infinity', () {
    const price = FieldSpec(
      'price',
      'Цена',
      kind: FieldKind.money,
      min: 0,
      max: 1000,
    );
    expect(validate(price, 'NaN'), isNotNull);
    expect(validate(price, 'Infinity'), isNotNull);
    expect(validate(price, '12,50'), isNull);
  });
  for (final role in Role.values) {
    test('${role.name} has its own exclusive section', () {
      expect(canOpen(role, '/admin'), role == Role.admin);
      expect(canOpen(role, '/workshop'), role == Role.master);
      expect(canOpen(role, '/garage'), role == Role.client);
    });
  }
  test('client routes restrict staff records and direct URLs', () {
    expect(canOpen(Role.client, '/data/users/anything'), false);
    expect(canOpen(Role.client, '/data/parts'), false);
    expect(canOpen(Role.client, '/data/orders/anything'), true);
    expect(canOpen(Role.master, '/data/users'), false);
  });
  test('return addresses cannot redirect to an external site', () {
    for (final input in [
      'https://example.com',
      '//example.com/x',
      '/login',
      'javascript:alert(1)',
    ]) {
      expect(safeNext(input), '/');
    }
    expect(
      safeNext('/data/orders?f.status=ready'),
      '/data/orders?f.status=ready',
    );
  });
  test('filter and page query survives URL round trip', () {
    const original = ListQuery(
      search: 'Киа & Toyota',
      page: 3,
      size: 20,
      sort: 'starts_at',
      archive: 'all',
      filters: {
        'status': 'ready',
        'master': 'master000000001',
        'from': '2026-11-02',
      },
    );
    final next = ListQuery.fromUri(
      Uri(path: '/data/orders', queryParameters: original.parameters),
    );
    expect(next.parameters, original.parameters);
  });
  test('search remains a JSON value and unrecognised filters are rejected', () {
    const query = ListQuery(
      search: '" || role = "admin',
      filters: {'status': 'ready', 'hacked) || true': '1'},
    );
    final payload = query.payload(entity('orders'));
    expect(payload['search'], '" || role = "admin');
    expect(payload['filters'], {'status': 'ready'});
  });
  test('sort and pagination are constrained before reaching the API', () {
    final query = ListQuery.fromUri(
      Uri.parse('/data/orders?page=-3&size=999&sort=nonexistent'),
    );
    expect(query.page, 1);
    expect(query.size, 10);
    expect(query.safeSort(entity('orders')), '-created');
  });
  test('server pagination and expanded relations are parsed', () {
    final page = RecordPage.fromJson({
      'page': 2,
      'totalPages': 3,
      'totalItems': 25,
      'items': [
        {
          'id': 'order1',
          'number': 'ЗН-1001',
          'expand': {
            'vehicle': {
              'id': 'car1',
              'brand': 'Kia',
              'model': 'Rio',
              'plate': 'М456КЕ799',
            },
          },
        },
      ],
    });
    expect(page.totalItems, 25);
    expect(page.page, 2);
    expect(page.items.single.relation('vehicle')!.label, 'Kia Rio · М456КЕ799');
  });
}
