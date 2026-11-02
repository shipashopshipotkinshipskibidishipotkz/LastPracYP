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

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'Управление сервисом',
          'Сотрудники, рабочие места и справочники администратора',
        ),
        LayoutBuilder(
          builder:
              (context, box) => Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final key in ['users', 'profiles', 'bays', 'categories'])
                    SizedBox(
                      width:
                          box.maxWidth < 700
                              ? box.maxWidth
                              : (box.maxWidth - 20) / 2,
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(entity(key).icon, color: accent, size: 28),
                            const SizedBox(height: 20),
                            Text(
                              entity(key).title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              entity(key).description,
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 22),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/data/$key'),
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: const Text('Открыть'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
        ),
      ],
    ),
  );
}

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});
  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  List<Record>? _cars;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _cars = null;
      _error = null;
    });
    try {
      final cars = await context.read<Repository>().options('vehicles');
      if (mounted) setState(() => _cars = cars);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Мой гараж',
          'Ваши автомобили и история обслуживания',
          action: FilledButton.icon(
            onPressed: () => context.go('/data/vehicles/new'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить автомобиль'),
          ),
        ),
        if (_error != null)
          Panel(child: ErrorState(_error!, _load))
        else if (_cars == null)
          const Panel(child: LoadingState())
        else if (_cars!.isEmpty)
          Panel(
            child: EmptyState(
              title: 'Добавьте ваш автомобиль',
              message: 'После этого можно записаться на обслуживание.',
              action: 'Добавить автомобиль',
              onAction: () => context.go('/data/vehicles/new'),
            ),
          )
        else
          LayoutBuilder(
            builder:
                (context, box) => Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final car in _cars!)
                      SizedBox(
                        width:
                            box.maxWidth < 700
                                ? box.maxWidth
                                : (box.maxWidth - 20) / 2,
                        child: Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.directions_car_outlined,
                                size: 42,
                                color: muted,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '${car.text('brand')} ${car.text('model')}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${car.text('plate')} · ${car.number('year').toInt()} г. · ${car.number('mileage').toInt()} км',
                                style: const TextStyle(color: muted),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton(
                                    onPressed: () => context.go('/booking'),
                                    child: const Text('Записаться'),
                                  ),
                                  OutlinedButton(
                                    onPressed:
                                        () => context.go(
                                          '/data/orders?f.vehicle=${car.id}',
                                        ),
                                    child: const Text('История'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          ),
      ],
    ),
  );
}

class WorkshopScreen extends StatefulWidget {
  const WorkshopScreen({super.key});
  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  Map<String, List<Record>>? _columns;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _columns = null;
      _error = null;
    });
    try {
      final repo = context.read<Repository>(),
          id = context.read<AuthState>().user!.id;
      final results = <String, List<Record>>{};
      await Future.wait(
        ['new', 'scheduled', 'in_progress', 'ready'].map((status) async {
          results[status] = await repo.options(
            'orders',
            filters: {'status': status, if (status != 'new') 'master': id},
          );
        }),
      );
      if (mounted) setState(() => _columns = results);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _advance(Record order, String status) async {
    setState(() => _busy = true);
    try {
      await context.read<Repository>().save(entity('orders'), {
        'status': status,
      }, id: order.id);
      await _load();
    } on ApiFailure catch (e) {
      if (mounted) notify(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Рабочий день мастера',
          'Новые заявки и назначенные вам автомобили',
          action: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Обновить'),
          ),
        ),
        if (_error != null)
          Panel(child: ErrorState(_error!, _load))
        else if (_columns == null)
          const Panel(child: LoadingState())
        else
          LayoutBuilder(
            builder: (context, box) {
              final count =
                  box.maxWidth < 600
                      ? 1
                      : box.maxWidth < 1200
                      ? 2
                      : 4;
              return Wrap(
                spacing: 16,
                runSpacing: 20,
                children: [
                  for (final status in [
                    'new',
                    'scheduled',
                    'in_progress',
                    'ready',
                  ])
                    SizedBox(
                      width: (box.maxWidth - (count - 1) * 16) / count,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                StatusBadge(status),
                                const Spacer(),
                                Text(
                                  '${_columns![status]!.length}',
                                  style: const TextStyle(color: muted),
                                ),
                              ],
                            ),
                          ),
                          if (_columns![status]!.isEmpty)
                            const Panel(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'Нет заказов',
                                  style: TextStyle(color: muted),
                                ),
                              ),
                            ),
                          for (final r in _columns![status]!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Panel(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.label,
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      r.relation('vehicle')?.label ??
                                          'Автомобиль',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      r.text('complaint'),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      dateLabel(r.text('starts_at')),
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed:
                                              () => context.go(
                                                '/data/orders/${r.id}',
                                              ),
                                          child: const Text('Открыть'),
                                        ),
                                        if (status == 'new')
                                          OutlinedButton(
                                            onPressed:
                                                () => context.go(
                                                  '/data/orders/${r.id}/edit',
                                                ),
                                            child: const Text('Назначить'),
                                          )
                                        else
                                          FilledButton(
                                            onPressed:
                                                _busy
                                                    ? null
                                                    : () => _advance(
                                                      r,
                                                      status == 'scheduled'
                                                          ? 'in_progress'
                                                          : status ==
                                                              'in_progress'
                                                          ? 'ready'
                                                          : 'closed',
                                                    ),
                                            child: Text(
                                              status == 'scheduled'
                                                  ? 'В работу'
                                                  : status == 'in_progress'
                                                  ? 'Готово'
                                                  : 'Выдать',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class ScheduleScreen extends StatefulWidget {
  final Uri uri;
  const ScheduleScreen(this.uri, {super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Record>? _orders, _bays;
  String? _error;
  DateTime get _day =>
      DateTime.tryParse(widget.uri.queryParameters['date'] ?? '') ??
      DateTime.now();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ScheduleScreen old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) _load();
  }

  void _go(DateTime day) =>
      context.go('/schedule?date=${inputDate(day).split(' ').first}');
  Future<void> _load() async {
    setState(() {
      _orders = null;
      _error = null;
    });
    try {
      final day = DateTime(_day.year, _day.month, _day.day);
      final repo = context.read<Repository>();
      final result = await Future.wait([
        repo.options(
          'orders',
          filters: {
            'from': apiDate(day),
            'to': apiDate(
              day
                  .add(const Duration(days: 1))
                  .subtract(const Duration(milliseconds: 1)),
            ),
          },
        ),
        repo.options('bays'),
      ]);
      if (mounted) {
        setState(() {
          _orders =
              result[0]..sort(
                (a, b) => a.text('starts_at').compareTo(b.text('starts_at')),
              );
          _bays = result[1];
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'Расписание постов',
          'Сервер проверяет пересечения поста, мастера и автомобиля',
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            IconButton(
              tooltip: 'Предыдущий день',
              onPressed: () => _go(_day.subtract(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (date != null && mounted) _go(date);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(inputDate(_day).split(' ').first),
            ),
            IconButton(
              tooltip: 'Следующий день',
              onPressed: () => _go(_day.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => _go(DateTime.now()),
              child: const Text('Сегодня'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Panel(child: ErrorState(_error!, _load))
        else if (_orders == null)
          const Panel(child: LoadingState())
        else
          LayoutBuilder(
            builder: (context, box) {
              final count =
                  box.maxWidth < 600
                      ? 1
                      : box.maxWidth < 1100
                      ? 2
                      : 4;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final bay in _bays!)
                    SizedBox(
                      width: (box.maxWidth - (count - 1) * 16) / count,
                      child: Panel(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bay.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              bayKinds[bay.text('kind')] ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (!_orders!.any((r) => r.text('bay') == bay.id))
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'Свободен весь день',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ),
                            for (final r in _orders!.where(
                              (r) => r.text('bay') == bay.id,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: InkWell(
                                  onTap:
                                      () => context.go('/data/orders/${r.id}'),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: canvas,
                                      borderRadius: BorderRadius.circular(8),
                                      border: const Border(
                                        left: BorderSide(
                                          color: accent,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${dateLabel(r.text('starts_at')).split(' · ').last}–${dateLabel(r.text('ends_at')).split(' · ').last}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          r.relation('vehicle')?.label ??
                                              r.label,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 8),
                                        StatusBadge(r.text('status')),
                                      ],
                                    ),
                                  ),
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
        if (_orders != null && _orders!.any((r) => r.text('bay').isEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              'Без назначения поста: ${_orders!.where((r) => r.text('bay').isEmpty).length}. Откройте «Рабочий день», чтобы назначить пост.',
              style: const TextStyle(color: muted),
            ),
          ),
      ],
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController(),
      _specialization = TextEditingController();
  Record? _profile;
  String? _error;
  bool _loading = true, _busy = false;
  Map<String, String> _errors = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _specialization.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<Repository>().list(
        entity('profiles'),
        ListQuery(filters: {'user': context.read<AuthState>().user!.id}),
      );
      if (mounted) {
        setState(() {
          _profile = result.items.firstOrNull;
          _phone.text = _profile?.text('phone') ?? '';
          _specialization.text = _profile?.text('specialization') ?? '';
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

  Future<void> _save() async {
    setState(() {
      _errors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    if (_profile == null) {
      notify(context, 'Профиль отсутствует. Обратитесь к администратору.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<Repository>().save(entity('profiles'), {
        'phone': _phone.text.trim(),
        'specialization': _specialization.text.trim(),
      }, id: _profile!.id);
      if (mounted) notify(context, 'Профиль сохранён');
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errors = e.fields;
        });
        _form.currentState!.validate();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            'Мой профиль',
            'Учётная запись и контактная информация',
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Panel(
              child:
                  _loading
                      ? const LoadingState()
                      : _error != null && _profile == null
                      ? ErrorState(_error!, _load)
                      : Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.user?.label ?? '',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${auth.user?.text('email')} · ${auth.role.title}',
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 28),
                            TextFormField(
                              controller: _phone,
                              decoration: const InputDecoration(
                                labelText: 'Телефон',
                              ),
                              validator:
                                  (value) =>
                                      _errors['phone'] ??
                                      validate(
                                        const FieldSpec(
                                          'phone',
                                          'Телефон',
                                          kind: FieldKind.phone,
                                          required: false,
                                          maxLength: 20,
                                        ),
                                        value,
                                      ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _specialization,
                              decoration: const InputDecoration(
                                labelText: 'Специализация / примечание',
                              ),
                              validator:
                                  (value) =>
                                      _errors['specialization'] ??
                                      validate(
                                        const FieldSpec(
                                          'specialization',
                                          'Специализация',
                                          required: false,
                                          maxLength: 120,
                                        ),
                                        value,
                                      ),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _busy ? null : _save,
                              child: const Text('Сохранить'),
                            ),
                          ],
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
