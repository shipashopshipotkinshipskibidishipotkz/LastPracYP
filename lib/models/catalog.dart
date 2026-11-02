import 'package:flutter/material.dart';
import 'record.dart';

enum FieldKind {
  text,
  multiline,
  integer,
  money,
  email,
  phone,
  password,
  dateTime,
  choice,
  relation,
  multiple,
}

class FieldSpec {
  final String key, label;
  final FieldKind kind;
  final bool required;
  final int maxLength;
  final double? min, max;
  final String? target;
  final Map<String, String> options;
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.required = true,
    this.maxLength = 120,
    this.min,
    this.max,
    this.target,
    this.options = const {},
  });
}

const statuses = {
  'new': 'Новая заявка',
  'scheduled': 'Запланирован',
  'in_progress': 'В работе',
  'ready': 'Готов к выдаче',
  'closed': 'Завершён',
  'cancelled': 'Отменён',
};
const roles = {
  'admin': 'Администратор',
  'master': 'Мастер',
  'client': 'Клиент',
};
const conditions = {
  'good': 'Исправно',
  'attention': 'Нужно внимание',
  'critical': 'Требуется ремонт',
};
const bayKinds = {
  'universal': 'Универсальный',
  'diagnostics': 'Диагностика',
  'tires': 'Шиномонтаж',
};

class EntitySpec {
  final String key, title, singular, description;
  final IconData icon;
  final List<FieldSpec> fields;
  final List<String> columns, search;
  final bool adminOnly;
  const EntitySpec(
    this.key,
    this.title,
    this.singular,
    this.description,
    this.icon,
    this.fields,
    this.columns,
    this.search, {
    this.adminOnly = false,
  });
  String get expand =>
      fields.where((f) => f.target != null).map((f) => f.key).join(',');
  bool canWrite(Role role) =>
      role == Role.admin ||
      (role == Role.master && !adminOnly) ||
      (role == Role.client && (key == 'vehicles' || key == 'orders'));
  bool canEdit(Role role) =>
      canWrite(role) && !(role == Role.client && key == 'orders');
  String label(String key) =>
      fields.where((f) => f.key == key).firstOrNull?.label ??
      const {
        'number': 'Номер',
        'total': 'Стоимость',
        'unit_price': 'Цена за ед.',
        'labor_total': 'Работы',
        'parts_total': 'Запчасти',
        'created': 'Создан',
        'updated': 'Изменён',
      }[key] ??
      key;
}

const entities = <EntitySpec>[
  EntitySpec(
    'orders',
    'Заказ-наряды',
    'Заказ-наряд',
    'От заявки до выдачи автомобиля',
    Icons.receipt_long_outlined,
    [
      FieldSpec(
        'vehicle',
        'Автомобиль',
        kind: FieldKind.relation,
        target: 'vehicles',
      ),
      FieldSpec(
        'services',
        'Услуги',
        kind: FieldKind.multiple,
        target: 'services',
      ),
      FieldSpec(
        'master',
        'Мастер',
        kind: FieldKind.relation,
        target: 'users',
        required: false,
      ),
      FieldSpec(
        'bay',
        'Пост',
        kind: FieldKind.relation,
        target: 'bays',
        required: false,
      ),
      FieldSpec('status', 'Статус', kind: FieldKind.choice, options: statuses),
      FieldSpec('starts_at', 'Начало', kind: FieldKind.dateTime),
      FieldSpec('ends_at', 'Окончание', kind: FieldKind.dateTime),
      FieldSpec(
        'complaint',
        'Обращение клиента',
        kind: FieldKind.multiline,
        maxLength: 2000,
      ),
      FieldSpec(
        'notes',
        'Заметки мастера',
        kind: FieldKind.multiline,
        required: false,
        maxLength: 2000,
      ),
      FieldSpec(
        'discount',
        'Скидка на работы, %',
        kind: FieldKind.integer,
        min: 0,
        max: 30,
      ),
    ],
    ['number', 'vehicle', 'status', 'starts_at', 'master', 'total'],
    [
      'number',
      'vehicle.plate',
      'vehicle.brand',
      'vehicle.model',
      'vehicle.customer.name',
      'complaint',
    ],
  ),
  EntitySpec(
    'customers',
    'Клиенты',
    'Клиент',
    'Контакты, автомобили и персональные скидки',
    Icons.people_outline,
    [
      FieldSpec('name', 'ФИО', maxLength: 100),
      FieldSpec('phone', 'Телефон', kind: FieldKind.phone, maxLength: 20),
      FieldSpec('email', 'Email', kind: FieldKind.email, required: false),
      FieldSpec(
        'account',
        'Учётная запись',
        kind: FieldKind.relation,
        target: 'users',
        required: false,
      ),
      FieldSpec(
        'discount',
        'Скидка на работы, %',
        kind: FieldKind.integer,
        min: 0,
        max: 30,
      ),
    ],
    ['name', 'phone', 'email', 'discount'],
    ['name', 'phone', 'email'],
  ),
  EntitySpec(
    'vehicles',
    'Автомобили',
    'Автомобиль',
    'История обслуживания и данные владельцев',
    Icons.directions_car_outlined,
    [
      FieldSpec(
        'customer',
        'Владелец',
        kind: FieldKind.relation,
        target: 'customers',
      ),
      FieldSpec('brand', 'Марка', maxLength: 40),
      FieldSpec('model', 'Модель', maxLength: 60),
      FieldSpec('plate', 'Госномер', maxLength: 12),
      FieldSpec('vin', 'VIN', maxLength: 17),
      FieldSpec(
        'year',
        'Год выпуска',
        kind: FieldKind.integer,
        min: 1950,
        max: 2100,
      ),
      FieldSpec(
        'mileage',
        'Пробег, км',
        kind: FieldKind.integer,
        min: 0,
        max: 3000000,
      ),
    ],
    ['plate', 'brand', 'model', 'customer', 'year', 'mileage'],
    ['plate', 'brand', 'model', 'vin', 'customer.name'],
  ),
  EntitySpec(
    'services',
    'Услуги',
    'Услуга',
    'Работы, стоимость и длительность',
    Icons.build_outlined,
    [
      FieldSpec('name', 'Название', maxLength: 100),
      FieldSpec(
        'category',
        'Категория',
        kind: FieldKind.relation,
        target: 'categories',
      ),
      FieldSpec(
        'price',
        'Стоимость, ₽',
        kind: FieldKind.money,
        min: 0,
        max: 500000,
      ),
      FieldSpec(
        'duration',
        'Длительность, мин',
        kind: FieldKind.integer,
        min: 5,
        max: 1440,
      ),
      FieldSpec(
        'description',
        'Описание',
        kind: FieldKind.multiline,
        required: false,
        maxLength: 1000,
      ),
    ],
    ['name', 'category', 'price', 'duration'],
    ['name', 'description', 'category.name'],
    adminOnly: true,
  ),
  EntitySpec(
    'parts',
    'Запчасти',
    'Запчасть',
    'Каталог расходников и наличие',
    Icons.inventory_2_outlined,
    [
      FieldSpec('name', 'Название', maxLength: 100),
      FieldSpec('sku', 'Артикул', maxLength: 40),
      FieldSpec('manufacturer', 'Производитель', maxLength: 60),
      FieldSpec(
        'price',
        'Цена, ₽',
        kind: FieldKind.money,
        min: 0,
        max: 1000000,
      ),
      FieldSpec(
        'stock',
        'В наличии, шт.',
        kind: FieldKind.integer,
        min: 0,
        max: 100000,
      ),
    ],
    ['name', 'sku', 'manufacturer', 'price', 'stock'],
    ['name', 'sku', 'manufacturer'],
    adminOnly: true,
  ),
  EntitySpec(
    'categories',
    'Категории услуг',
    'Категория',
    'Направления обслуживания',
    Icons.category_outlined,
    [
      FieldSpec('name', 'Название', maxLength: 80),
      FieldSpec(
        'description',
        'Описание',
        kind: FieldKind.multiline,
        required: false,
        maxLength: 500,
      ),
    ],
    ['name', 'description'],
    ['name', 'description'],
    adminOnly: true,
  ),
  EntitySpec(
    'bays',
    'Рабочие посты',
    'Рабочий пост',
    'Оснащение и назначение рабочих мест',
    Icons.garage_outlined,
    [
      FieldSpec('name', 'Название', maxLength: 60),
      FieldSpec(
        'kind',
        'Назначение',
        kind: FieldKind.choice,
        options: bayKinds,
      ),
      FieldSpec(
        'equipment',
        'Оборудование',
        kind: FieldKind.multiline,
        maxLength: 500,
        required: false,
      ),
    ],
    ['name', 'kind', 'equipment'],
    ['name', 'equipment'],
    adminOnly: true,
  ),
  EntitySpec(
    'order_services',
    'Работы заказов',
    'Работа заказа',
    'Услуги в заказ-нарядах и зафиксированная стоимость',
    Icons.assignment_outlined,
    [
      FieldSpec(
        'order',
        'Заказ-наряд',
        kind: FieldKind.relation,
        target: 'orders',
      ),
      FieldSpec(
        'service',
        'Услуга',
        kind: FieldKind.relation,
        target: 'services',
      ),
    ],
    ['order', 'service', 'unit_price'],
    ['order.number', 'service.name'],
  ),
  EntitySpec(
    'order_parts',
    'Материалы заказов',
    'Материал заказа',
    'Использованные запчасти с сохранением цены',
    Icons.handyman_outlined,
    [
      FieldSpec(
        'order',
        'Заказ-наряд',
        kind: FieldKind.relation,
        target: 'orders',
      ),
      FieldSpec('part', 'Запчасть', kind: FieldKind.relation, target: 'parts'),
      FieldSpec(
        'quantity',
        'Количество, шт.',
        kind: FieldKind.integer,
        min: 1,
        max: 1000,
      ),
    ],
    ['order', 'part', 'quantity', 'unit_price'],
    ['order.number', 'part.name', 'part.sku'],
  ),
  EntitySpec(
    'inspections',
    'Диагностика',
    'Диагностическая карта',
    'Состояние автомобиля и рекомендации',
    Icons.fact_check_outlined,
    [
      FieldSpec(
        'order',
        'Заказ-наряд',
        kind: FieldKind.relation,
        target: 'orders',
      ),
      FieldSpec(
        'condition',
        'Состояние',
        kind: FieldKind.choice,
        options: conditions,
      ),
      FieldSpec(
        'findings',
        'Результаты осмотра',
        kind: FieldKind.multiline,
        maxLength: 3000,
      ),
      FieldSpec(
        'recommendations',
        'Рекомендации',
        kind: FieldKind.multiline,
        maxLength: 2000,
        required: false,
      ),
      FieldSpec(
        'mileage',
        'Пробег, км',
        kind: FieldKind.integer,
        min: 0,
        max: 3000000,
      ),
    ],
    ['order', 'condition', 'findings', 'mileage'],
    ['order.number', 'findings', 'recommendations'],
  ),
  EntitySpec(
    'users',
    'Сотрудники и доступ',
    'Учётная запись',
    'Роли пользователей и управление доступом',
    Icons.admin_panel_settings_outlined,
    [
      FieldSpec('name', 'ФИО', maxLength: 100),
      FieldSpec('email', 'Email', kind: FieldKind.email),
      FieldSpec('role', 'Роль', kind: FieldKind.choice, options: roles),
      FieldSpec('password', 'Пароль', kind: FieldKind.password, maxLength: 72),
    ],
    ['name', 'email', 'role'],
    ['name', 'email'],
    adminOnly: true,
  ),
  EntitySpec(
    'profiles',
    'Профили',
    'Профиль',
    'Контакты и специализация сотрудников',
    Icons.badge_outlined,
    [
      FieldSpec(
        'user',
        'Пользователь',
        kind: FieldKind.relation,
        target: 'users',
      ),
      FieldSpec(
        'phone',
        'Телефон',
        kind: FieldKind.phone,
        maxLength: 20,
        required: false,
      ),
      FieldSpec(
        'specialization',
        'Специализация',
        maxLength: 120,
        required: false,
      ),
    ],
    ['user', 'phone', 'specialization'],
    ['user.name', 'phone', 'specialization'],
    adminOnly: true,
  ),
];

EntitySpec entity(String key) => entities.firstWhere((e) => e.key == key);

bool canOpen(Role role, String path) {
  if (path == '/' || path == '/profile') return true;
  if (path.startsWith('/admin')) return role == Role.admin;
  if (path.startsWith('/workshop') || path.startsWith('/schedule')) {
    return role == Role.master;
  }
  if (path.startsWith('/garage') || path.startsWith('/booking')) {
    return role == Role.client;
  }
  if (path.startsWith('/data/')) {
    final key = path.split('/')[2];
    if (!entities.any((e) => e.key == key)) return false;
    return role == Role.admin ||
        (role == Role.master && !['users', 'profiles'].contains(key)) ||
        (role == Role.client &&
            ['orders', 'vehicles', 'services', 'inspections'].contains(key));
  }
  return path == '/forbidden';
}
