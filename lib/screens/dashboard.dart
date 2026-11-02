import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../models/record.dart';
import '../repositories/repository.dart';
import '../state/auth_state.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Record> _orders = [];
  int _cars = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<Repository>();
      final orders = await repo.options('orders');
      final cars = await repo.list(
        entity('vehicles'),
        const ListQuery(size: 10),
      );
      if (mounted) {
        setState(() {
          _orders = orders;
          _cars = cars.totalItems;
          _loading = false;
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>(), role = auth.role;
    final work = _orders.where((r) => r.text('status') == 'in_progress').length;
    final ready = _orders.where((r) => r.text('status') == 'ready').length;
    final scheduled =
        _orders.where((r) => r.text('status') == 'scheduled').length;
    final now = DateTime.now();
    final closed = _orders.where((r) {
      final date = DateTime.tryParse(r.text('updated'))?.toLocal();
      return r.text('status') == 'closed' &&
          date?.year == now.year &&
          date?.month == now.month;
    });
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            role == Role.client
                ? 'Ваш автомобиль в надёжных руках'
                : 'Обзор автосервиса',
            role == Role.client
                ? 'Записи, обслуживание и история ваших автомобилей'
                : 'Всё важное для спокойного рабочего дня',
            action: FilledButton.icon(
              onPressed:
                  () => context.go(
                    role == Role.client ? '/booking' : '/data/orders/new',
                  ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                role == Role.client ? 'Записаться' : 'Новый заказ-наряд',
              ),
            ),
          ),
          if (_loading)
            const Panel(child: LoadingState())
          else if (_error != null)
            Panel(child: ErrorState(_error!, _load))
          else ...[
            LayoutBuilder(
              builder: (context, box) {
                final count = box.maxWidth < 550 ? 2 : 4;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final stat in [
                      (
                        role == Role.client
                            ? 'Мои автомобили'
                            : 'Автомобилей в базе',
                        '$_cars',
                        Icons.directions_car_outlined,
                      ),
                      (
                        'Запланировано',
                        '$scheduled',
                        Icons.calendar_today_outlined,
                      ),
                      ('В работе', '$work', Icons.build_outlined),
                      ('Готово к выдаче', '$ready', Icons.check_circle_outline),
                    ])
                      SizedBox(
                        width: (box.maxWidth - 16 * (count - 1)) / count,
                        child: Panel(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(stat.$3, color: muted, size: 22),
                              const SizedBox(height: 20),
                              Text(
                                stat.$2,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                stat.$1,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            LayoutBuilder(
              builder: (context, box) {
                final left = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ближайшие записи',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton(
                            onPressed:
                                () => context.go('/data/orders?sort=starts_at'),
                            child: const Text('Все'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_orders.isEmpty)
                        EmptyState(
                          title: 'Заказов пока нет',
                          message: 'Создайте первую запись на обслуживание.',
                          action: 'Записаться',
                          onAction:
                              () => context.go(
                                role == Role.client
                                    ? '/booking'
                                    : '/data/orders/new',
                              ),
                        ),
                      for (final order in (_orders
                              .where(
                                (r) =>
                                    ![
                                      'closed',
                                      'cancelled',
                                    ].contains(r.text('status')),
                              )
                              .toList()
                            ..sort(
                              (a, b) => a
                                  .text('starts_at')
                                  .compareTo(b.text('starts_at')),
                            ))
                          .take(6))
                        InkWell(
                          onTap: () => context.go('/data/orders/${order.id}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: canvas,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.directions_car_outlined,
                                    color: muted,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        order.relation('vehicle')?.label ??
                                            order.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${order.label} · ${dateLabel(order.text('starts_at'))}',
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      StatusBadge(order.text('status')),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: muted,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
                final right = Column(
                  children: [
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            role == Role.client
                                ? 'Понятная стоимость'
                                : 'Заказ-наряды по статусам',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 20),
                          if (role == Role.client) ...[
                            const Text(
                              'Скидка применяется к работам. Запчасти считаются отдельно по цене на момент добавления.',
                              style: TextStyle(color: muted),
                            ),
                            const SizedBox(height: 18),
                            OutlinedButton(
                              onPressed: () => context.go('/data/services'),
                              child: const Text('Посмотреть услуги'),
                            ),
                          ] else
                            for (final status in statuses.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            status.value,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${_orders.where((r) => r.text('status') == status.key).length}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        minHeight: 5,
                                        value:
                                            _orders.isEmpty
                                                ? 0
                                                : _orders
                                                        .where(
                                                          (r) =>
                                                              r.text(
                                                                'status',
                                                              ) ==
                                                              status.key,
                                                        )
                                                        .length /
                                                    _orders.length,
                                        backgroundColor: canvas,
                                        color:
                                            status.key == 'in_progress'
                                                ? accent
                                                : const Color(0xFF879D8D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    if (role == Role.admin) ...[
                      const SizedBox(height: 20),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Выручка за текущий месяц',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              money(
                                closed.fold(
                                  0.0,
                                  (sum, r) => sum + r.number('total'),
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'По завершённым заказам: ${closed.length}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
                return box.maxWidth < 950
                    ? Column(
                      children: [left, const SizedBox(height: 20), right],
                    )
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: left),
                        const SizedBox(width: 24),
                        Expanded(flex: 4, child: right),
                      ],
                    );
              },
            ),
          ],
        ],
      ),
    );
  }
}
