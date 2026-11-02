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
import '../widgets/record_value.dart';

class EntityDetailScreen extends StatefulWidget {
  final EntitySpec spec;
  final String id;
  const EntityDetailScreen(this.spec, this.id, {super.key});
  @override
  State<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends State<EntityDetailScreen> {
  Record? _record;
  String? _error;
  bool _loading = true;
  List<Record> _parts = [], _inspections = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EntityDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.spec != widget.spec) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<Repository>();
      final record = await repo.get(widget.spec, widget.id);
      if (widget.spec.key == 'orders') {
        final results = await Future.wait([
          repo.list(
            entity('order_parts'),
            ListQuery(filters: {'order': widget.id}, size: 50),
          ),
          repo.list(
            entity('inspections'),
            ListQuery(filters: {'order': widget.id}, size: 10),
          ),
        ]);
        _parts = results[0].items;
        _inspections = results[1].items;
      }
      if (mounted) {
        setState(() {
          _record = record;
          _loading = false;
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Panel(child: LoadingState());
    if (_error != null) return Panel(child: ErrorState(_error!, _load));
    final r = _record!, role = context.watch<AuthState>().role;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => context.go('/data/${widget.spec.key}'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(widget.spec.title),
          ),
          const SizedBox(height: 12),
          PageHeading(
            r.label,
            '${widget.spec.singular}${r.archived ? ' · В архиве' : ''}',
            action:
                widget.spec.canEdit(role)
                    ? OutlinedButton.icon(
                      onPressed:
                          () => context.go(
                            '/data/${widget.spec.key}/${r.id}/edit',
                          ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Редактировать'),
                    )
                    : null,
          ),
          if (widget.spec.key == 'orders') ...[
            _cost(r),
            const SizedBox(height: 20),
          ],
          Panel(
            child: LayoutBuilder(
              builder:
                  (context, box) => Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      for (final f in widget.spec.fields.where(
                        (f) => f.kind != FieldKind.password,
                      ))
                        SizedBox(
                          width:
                              box.maxWidth < 650 ||
                                      f.kind == FieldKind.multiline ||
                                      f.kind == FieldKind.multiple
                                  ? box.maxWidth
                                  : (box.maxWidth - 24) / 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.label,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (f.target != null &&
                                  r.relation(f.key) != null &&
                                  canOpen(role, '/data/${f.target}'))
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    alignment: Alignment.centerLeft,
                                  ),
                                  onPressed:
                                      () => context.go(
                                        '/data/${f.target}/${r.relation(f.key)!.id}',
                                      ),
                                  child: Text(
                                    recordValue(widget.spec, r, f.key),
                                  ),
                                )
                              else
                                SelectableText(
                                  recordValue(widget.spec, r, f.key),
                                ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: box.maxWidth,
                        child: Text(
                          'Создан: ${dateLabel(r.text('created'))} · Изменён: ${dateLabel(r.text('updated'))}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
            ),
          ),
          if (widget.spec.key == 'orders') ...[
            const SizedBox(height: 24),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Запчасти и материалы',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  if (_parts.isEmpty)
                    const Text(
                      'Материалы пока не добавлены',
                      style: TextStyle(color: muted),
                    ),
                  for (final p in _parts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.relation('part')?.label ?? p.id),
                      subtitle: Text(
                        '${p.number('quantity').toInt()} шт. × ${money(p.number('unit_price'))}',
                      ),
                      trailing: Text(
                        money(p.number('quantity') * p.number('unit_price')),
                      ),
                    ),
                  if (role != Role.client)
                    TextButton.icon(
                      onPressed: () => context.go('/data/order_parts/new'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить материал'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Диагностическая карта',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_inspections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text(
                        'Осмотр ещё не проведён',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  for (final item in _inspections) ...[
                    const SizedBox(height: 14),
                    StatusBadge(item.text('condition')),
                    const SizedBox(height: 12),
                    Text(item.text('findings')),
                    const SizedBox(height: 8),
                    Text(
                      item.text('recommendations'),
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cost(Record r) => Panel(
    child: Wrap(
      spacing: 44,
      runSpacing: 20,
      children: [
        for (final entry
            in {
              'Работы': money(r.number('labor_total')),
              'Скидка на работы': '${r.number('discount').toInt()}%',
              'Запчасти': money(r.number('parts_total')),
              'Итого': money(r.number('total')),
            }.entries)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                entry.value,
                style: TextStyle(
                  fontSize: entry.key == 'Итого' ? 28 : 22,
                  fontWeight: FontWeight.w800,
                  color: entry.key == 'Итого' ? accent : ink,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
