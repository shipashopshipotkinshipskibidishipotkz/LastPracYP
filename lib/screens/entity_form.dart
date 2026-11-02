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

class EntityFormScreen extends StatefulWidget {
  final EntitySpec spec;
  final String? id;
  final bool booking;
  const EntityFormScreen(this.spec, {super.key, this.id, this.booking = false});
  @override
  State<EntityFormScreen> createState() => _EntityFormScreenState();
}

class _EntityFormScreenState extends State<EntityFormScreen> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _choices = <String, String>{};
  final _multiple = <String, List<String>>{};
  final _options = <String, List<Record>>{};
  Map<String, String> _errors = {};
  List<FieldSpec> _fields = [];
  bool _loading = true, _saving = false;
  String? _error;
  Record? _original;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EntityFormScreen old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec || old.id != widget.id) {
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _choices.clear();
      _multiple.clear();
      _options.clear();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final role = context.read<AuthState>().role;
    _fields =
        widget.spec.fields
            .where(
              (f) =>
                  !(role == Role.client &&
                      widget.spec.key == 'orders' &&
                      [
                        'master',
                        'bay',
                        'status',
                        'notes',
                        'discount',
                      ].contains(f.key)),
            )
            .toList();
    try {
      final repo = context.read<Repository>();
      _original =
          widget.id == null ? null : await repo.get(widget.spec, widget.id!);
      await Future.wait(
        _fields.where((f) => f.target != null).map((f) async {
          _options[f.key] = await repo.options(
            f.target!,
            filters:
                f.key == 'master'
                    ? {'role': 'master'}
                    : f.key == 'account'
                    ? {'role': 'client'}
                    : const {},
          );
        }),
      );
      for (final f in _fields) {
        var value = _original?.text(f.key) ?? '';
        if (f.kind == FieldKind.choice) {
          _choices[f.key] = value.isEmpty ? f.options.keys.first : value;
        } else if (f.kind == FieldKind.relation) {
          _choices[f.key] =
              value.isEmpty && f.required && (_options[f.key]?.length ?? 0) == 1
                  ? _options[f.key]!.first.id
                  : value;
        } else if (f.kind == FieldKind.multiple) {
          _multiple[f.key] = _original?.ids(f.key) ?? [];
        } else {
          if (f.kind == FieldKind.dateTime) {
            value =
                value.isEmpty
                    ? inputDate(
                      DateTime.now()
                          .add(Duration(hours: f.key == 'ends_at' ? 2 : 1))
                          .copyWith(minute: 0),
                    )
                    : inputDate(DateTime.parse(value).toLocal());
          }
          if (value.isEmpty &&
              (f.kind == FieldKind.money || f.kind == FieldKind.integer)) {
            value = '${f.min?.toInt() ?? 0}';
          }
          _controllers[f.key]?.dispose();
          _controllers[f.key] = TextEditingController(
            text: f.kind == FieldKind.password ? '' : value,
          );
        }
      }
      if (mounted) setState(() => _loading = false);
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
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(FieldSpec f) async {
    final now = DateTime.now();
    final current =
        DateTime.tryParse(_controllers[f.key]!.text.replaceFirst(' ', 'T')) ??
        now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted || time == null) return;
    setState(() {
      _controllers[f.key]!.text = inputDate(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
      _errors.remove(f.key);
    });
  }

  Future<void> _save() async {
    setState(() {
      _errors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    final data = <String, dynamic>{};
    for (final f in _fields) {
      final value = _controllers[f.key]?.text.trim() ?? '';
      data[f.key] = switch (f.kind) {
        FieldKind.relation || FieldKind.choice => _choices[f.key] ?? '',
        FieldKind.multiple => _multiple[f.key] ?? <String>[],
        FieldKind.integer => double.parse(value.replaceAll(',', '.')).toInt(),
        FieldKind.money => double.parse(value.replaceAll(',', '.')),
        FieldKind.dateTime =>
          DateTime.parse(
            value.replaceFirst(' ', 'T'),
          ).toUtc().toIso8601String(),
        _ => value,
      };
      if (f.kind == FieldKind.password) {
        if (value.isEmpty) {
          data.remove(f.key);
        } else {
          data['passwordConfirm'] = value;
        }
      }
    }
    if (widget.spec.key == 'orders') {
      if (!DateTime.parse(
        data['ends_at'],
      ).isAfter(DateTime.parse(data['starts_at']))) {
        setState(
          () => _errors['ends_at'] = 'Окончание должно быть позже начала',
        );
        _form.currentState!.validate();
        return;
      }
      data.putIfAbsent('status', () => 'new');
    }
    setState(() => _saving = true);
    try {
      final record = await context.read<Repository>().save(
        widget.spec,
        data,
        id: widget.id,
      );
      if (mounted) {
        notify(
          context,
          widget.id == null ? 'Запись создана' : 'Изменения сохранены',
        );
        context.go('/data/${widget.spec.key}/${record.id}');
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
          _errors = e.fields;
        });
        _form.currentState!.validate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthState>().role;
    if (!(widget.id == null
        ? widget.spec.canWrite(role)
        : widget.spec.canEdit(role))) {
      return const EmptyState(
        title: 'Доступ закрыт',
        message: 'У вашей роли нет доступа к этой операции.',
        icon: Icons.lock_outline,
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed:
                () => context.go(
                  widget.id == null
                      ? '/data/${widget.spec.key}'
                      : '/data/${widget.spec.key}/${widget.id}',
                ),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Назад'),
          ),
          const SizedBox(height: 12),
          PageHeading(
            widget.booking
                ? 'Запись на обслуживание'
                : '${widget.id == null ? 'Новая запись' : 'Редактирование'}: ${widget.spec.singular.toLowerCase()}',
            widget.booking
                ? 'Выберите автомобиль и услуги. Мастер подтвердит время и назначит пост.'
                : widget.spec.description,
          ),
          if (_loading)
            const Panel(child: LoadingState())
          else if (_error != null && _controllers.isEmpty && _choices.isEmpty)
            Panel(child: ErrorState(_error!, _load))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Panel(
                child: Form(
                  key: _form,
                  child: LayoutBuilder(
                    builder:
                        (context, box) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 20,
                              runSpacing: 22,
                              children: [
                                for (final f in _fields)
                                  SizedBox(
                                    width:
                                        box.maxWidth < 650 ||
                                                f.kind == FieldKind.multiline ||
                                                f.kind == FieldKind.multiple
                                            ? box.maxWidth
                                            : (box.maxWidth - 20) / 2,
                                    child: _field(f),
                                  ),
                              ],
                            ),
                            if (widget.spec.key == 'orders') ...[
                              const SizedBox(height: 24),
                              _estimate(),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 20),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon:
                                      _saving
                                          ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(Icons.check, size: 18),
                                  label: Text(
                                    widget.booking
                                        ? 'Отправить заявку'
                                        : 'Сохранить',
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      _saving
                                          ? null
                                          : () => context.go(
                                            '/data/${widget.spec.key}',
                                          ),
                                  child: const Text('Отмена'),
                                ),
                              ],
                            ),
                          ],
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(FieldSpec f) {
    final label = '${f.label}${f.required ? ' *' : ''}';
    if (f.kind == FieldKind.choice || f.kind == FieldKind.relation) {
      final options =
          f.kind == FieldKind.choice
              ? f.options
              : {for (final r in _options[f.key] ?? <Record>[]) r.id: r.label};
      final selected = _choices[f.key];
      if (selected != null &&
          selected.isNotEmpty &&
          !options.containsKey(selected)) {
        options[selected] =
            _original?.relation(f.key)?.label ?? 'Архивная запись';
      }
      return DropdownButtonFormField<String>(
        value: selected?.isEmpty == true ? null : selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText:
              f.kind == FieldKind.relation && options.isEmpty
                  ? 'Нет доступных записей в справочнике'
                  : null,
        ),
        items: [
          if (!f.required)
            const DropdownMenuItem(value: '', child: Text('Не назначено')),
          for (final o in options.entries)
            DropdownMenuItem(
              value: o.key,
              child: Text(
                o.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        validator:
            (value) =>
                _errors[f.key] ??
                (f.required && (value == null || value.isEmpty)
                    ? 'Выберите значение'
                    : null),
        onChanged:
            _saving
                ? null
                : (value) {
                  setState(() {
                    _choices[f.key] = value ?? '';
                    _errors.remove(f.key);
                    if (widget.spec.key == 'orders' &&
                        f.key == 'vehicle' &&
                        widget.id == null) {
                      final car =
                          _options['vehicle']
                              ?.where((r) => r.id == value)
                              .firstOrNull;
                      _controllers['discount']?.text =
                          '${car?.relation('customer')?.number('discount').toInt() ?? 0}';
                    }
                  });
                },
      );
    }
    if (f.kind == FieldKind.multiple) {
      return FormField<List<String>>(
        validator:
            (_) =>
                _errors[f.key] ??
                (f.required && (_multiple[f.key]?.isEmpty ?? true)
                    ? 'Выберите хотя бы одну услугу'
                    : null),
        builder:
            (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color:
                          state.hasError
                              ? Theme.of(context).colorScheme.error
                              : line,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final record in _options[f.key] ?? <Record>[])
                        CheckboxListTile(
                          dense: true,
                          value: _multiple[f.key]?.contains(record.id) ?? false,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(record.label),
                          subtitle: Text(
                            '${money(record.number('price'))} · ${record.number('duration').toInt()} мин',
                          ),
                          onChanged:
                              _saving
                                  ? null
                                  : (value) {
                                    setState(() {
                                      final ids = _multiple.putIfAbsent(
                                        f.key,
                                        () => [],
                                      );
                                      value == true
                                          ? ids.add(record.id)
                                          : ids.remove(record.id);
                                      _errors.remove(f.key);
                                    });
                                    state.didChange(_multiple[f.key]);
                                  },
                        ),
                    ],
                  ),
                ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      state.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
      );
    }
    return TextFormField(
      controller: _controllers[f.key],
      enabled: !_saving,
      obscureText: f.kind == FieldKind.password,
      maxLines: f.kind == FieldKind.multiline ? 3 : 1,
      keyboardType: switch (f.kind) {
        FieldKind.integer ||
        FieldKind.money => const TextInputType.numberWithOptions(decimal: true),
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: f.kind == FieldKind.dateTime ? 'ГГГГ-ММ-ДД ЧЧ:ММ' : null,
        suffixIcon:
            f.kind == FieldKind.dateTime
                ? IconButton(
                  tooltip: 'Выбрать дату и время',
                  onPressed: () => _pickDate(f),
                  icon: const Icon(Icons.event_outlined),
                )
                : null,
      ),
      validator:
          (value) =>
              _errors[f.key] ?? validate(f, value, editing: widget.id != null),
      onChanged: (_) {
        if (_errors.containsKey(f.key)) setState(() => _errors.remove(f.key));
        if (f.key == 'discount') setState(() {});
      },
    );
  }

  Widget _estimate() {
    final selected = _multiple['services'] ?? [];
    final labor = (_options['services'] ?? [])
        .where((r) => selected.contains(r.id))
        .fold(0.0, (v, r) => v + r.number('price'));
    final car =
        _options['vehicle']
            ?.where((r) => r.id == _choices['vehicle'])
            .firstOrNull;
    final discount =
        double.tryParse(_controllers['discount']?.text ?? '') ??
        car?.relation('customer')?.number('discount') ??
        0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Предварительная стоимость работ',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 6),
          Text(
            money(orderTotal(labor, 0, discount)),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Text(
            'Скидка на работы: ${discount.toInt()}%. Запчасти добавляются отдельно. Итог рассчитывает сервер.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
