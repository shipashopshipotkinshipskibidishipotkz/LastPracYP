import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../models/record.dart';
import '../repositories/repository.dart';
import '../state/auth_state.dart';
import '../state/list_state.dart';
import '../widgets/common.dart';
import '../widgets/record_value.dart';

class EntityListScreen extends StatefulWidget {
  final EntitySpec spec;
  final Uri uri;
  const EntityListScreen(this.spec, this.uri, {super.key});
  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  late ListState _state;
  late ListQuery _query;
  late TextEditingController _search;
  final _selected = <String>{};
  final _options = <String, List<Record>>{};
  bool _filtersOpen = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _query = ListQuery.fromUri(widget.uri);
    _search = TextEditingController(text: _query.search);
    _filtersOpen = _query.filters.isNotEmpty;
    _state = ListState(context.read<Repository>(), widget.spec);
    _state.load(_query);
    _loadOptions();
  }

  @override
  void didUpdateWidget(EntityListScreen old) {
    super.didUpdateWidget(old);
    if (widget.spec.key != old.spec.key) {
      _state.dispose();
      _state = ListState(context.read<Repository>(), widget.spec);
      _options.clear();
      _loadOptions();
    }
    if (widget.uri != old.uri) {
      _query = ListQuery.fromUri(widget.uri);
      _search.text = _query.search;
      _selected.clear();
      _state.load(_query);
    }
  }

  Future<void> _loadOptions() async {
    final repository = context.read<Repository>();
    final state = _state;
    for (final f in _filterFields.where((f) => f.kind == FieldKind.relation)) {
      if (!mounted || state != _state) return;
      try {
        final result = await repository.options(
          f.target!,
          filters: f.key == 'master' ? {'role': 'master'} : const {},
        );
        if (!mounted || state != _state) return;
        setState(() => _options[f.key] = result);
      } on ApiFailure {
        /* The main list provides a visible retry if offline. */
      }
    }
  }

  List<FieldSpec> get _filterFields {
    final all =
        widget.spec.fields
            .where(
              (f) =>
                  ![
                    FieldKind.password,
                    FieldKind.multiline,
                    FieldKind.multiple,
                    FieldKind.dateTime,
                  ].contains(f.kind),
            )
            .toList();
    int rank(FieldSpec field) =>
        field.kind == FieldKind.choice
            ? 0
            : field.kind == FieldKind.relation
            ? 1
            : 2;
    all.sort((a, b) => rank(a).compareTo(rank(b)));
    return all.take(3).toList();
  }

  void _change(ListQuery query) => context.go(
    Uri(
      path: '/data/${widget.spec.key}',
      queryParameters: query.parameters.isEmpty ? null : query.parameters,
    ).toString(),
  );
  void _filter(String key, String value) {
    final filters = {..._query.filters};
    value.isEmpty ? filters.remove(key) : filters[key] = value;
    _change(_query.copy(filters: filters, page: 1));
  }

  @override
  void dispose() {
    _state.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _mutate(List<Record> records, String action) async {
    final permanent = action == 'delete';
    if (!await confirm(
      context,
      permanent
          ? 'Удалить навсегда?'
          : action == 'restore'
          ? 'Восстановить записи?'
          : 'Перенести в архив?',
      '${records.length == 1 ? records.first.label : 'Выбрано записей: ${records.length}'}. ${permanent ? 'Отменить физическое удаление нельзя.' : 'Записи можно будет найти в фильтре «Архив».'}',
      action:
          permanent
              ? 'Удалить'
              : action == 'restore'
              ? 'Восстановить'
              : 'В архив',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final repo = context.read<Repository>();
    var done = 0;
    final errors = <String>{};
    for (final record in records) {
      try {
        if (permanent) {
          await repo.delete(widget.spec, record.id);
        } else {
          await repo.archive(widget.spec, record.id, action != 'restore');
        }
        done++;
      } on ApiFailure catch (e) {
        errors.add(e.message);
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    notify(
      context,
      'Обработано: $done из ${records.length}.${errors.isEmpty ? '' : ' ${errors.join(' ')}'}',
    );
    await _state.load(_query);
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthState>().role;
    final spec = widget.spec;
    return ListenableBuilder(
      listenable: _state,
      builder:
          (context, _) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  spec.title,
                  spec.description,
                  action:
                      spec.canWrite(role)
                          ? FilledButton.icon(
                            onPressed:
                                () => context.go('/data/${spec.key}/new'),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Добавить'),
                          )
                          : null,
                ),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: LayoutBuilder(
                          builder:
                              (context, box) => Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width:
                                        box.maxWidth < 600
                                            ? box.maxWidth
                                            : (box.maxWidth - 290).clamp(
                                              240,
                                              520,
                                            ),
                                    child: TextField(
                                      controller: _search,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Поиск в ${spec.title.toLowerCase()}',
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          size: 20,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: 'Найти',
                                          onPressed:
                                              () => _change(
                                                _query.copy(
                                                  search: _search.text.trim(),
                                                  page: 1,
                                                ),
                                              ),
                                          icon: const Icon(
                                            Icons.arrow_forward,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      textInputAction: TextInputAction.search,
                                      onSubmitted:
                                          (value) => _change(
                                            _query.copy(
                                              search: value.trim(),
                                              page: 1,
                                            ),
                                          ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed:
                                        () => setState(
                                          () => _filtersOpen = !_filtersOpen,
                                        ),
                                    icon: const Icon(Icons.tune, size: 18),
                                    label: Text(
                                      'Фильтры${_query.filters.isEmpty ? '' : ' (${_query.filters.length})'}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Обновить список',
                                    onPressed: () => _state.load(_query),
                                    icon: const Icon(Icons.refresh, size: 21),
                                  ),
                                ],
                              ),
                        ),
                      ),
                      if (_filtersOpen)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: LayoutBuilder(
                            builder:
                                (context, box) => Wrap(
                                  spacing: 12,
                                  runSpacing: 16,
                                  children: [
                                    for (final f in _filterFields)
                                      SizedBox(
                                        width:
                                            box.maxWidth < 500
                                                ? box.maxWidth
                                                : 210,
                                        child: _filterField(f),
                                      ),
                                    for (final key in ['from', 'to'])
                                      SizedBox(
                                        width:
                                            box.maxWidth < 500
                                                ? box.maxWidth
                                                : 180,
                                        child: TextFormField(
                                          key: ValueKey(
                                            '${spec.key}:$key:${_query.filters[key]}',
                                          ),
                                          initialValue: _query.filters[key],
                                          decoration: InputDecoration(
                                            labelText:
                                                key == 'from'
                                                    ? 'Дата с'
                                                    : 'Дата по',
                                            hintText: 'ГГГГ-ММ-ДД',
                                          ),
                                          onFieldSubmitted: (value) {
                                            if (value.isEmpty ||
                                                DateTime.tryParse(value) !=
                                                    null) {
                                              _filter(key, value);
                                            } else {
                                              notify(
                                                context,
                                                'Формат даты: ГГГГ-ММ-ДД',
                                              );
                                            }
                                          },
                                          onTapOutside:
                                              (_) =>
                                                  FocusScope.of(
                                                    context,
                                                  ).unfocus(),
                                        ),
                                      ),
                                    TextButton(
                                      onPressed:
                                          () => _change(const ListQuery()),
                                      child: const Text('Сбросить всё'),
                                    ),
                                  ],
                                ),
                          ),
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${_state.result?.totalItems ?? 0} записей',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _query.archive,
                                  isDense: true,
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'active',
                                      child: Text('Активные'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'archived',
                                      child: Text('Архив'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('Все записи'),
                                    ),
                                  ],
                                  onChanged:
                                      (value) => _change(
                                        _query.copy(archive: value!, page: 1),
                                      ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 210,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _query.safeSort(spec),
                                  isDense: true,
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(
                                      value: '-created',
                                      child: Text('Сначала новые'),
                                    ),
                                    const DropdownMenuItem(
                                      value: 'created',
                                      child: Text('Сначала старые'),
                                    ),
                                    for (final key in spec.columns.take(3)) ...[
                                      DropdownMenuItem(
                                        value: key,
                                        child: Text('${spec.label(key)} ↑'),
                                      ),
                                      DropdownMenuItem(
                                        value: '-$key',
                                        child: Text('${spec.label(key)} ↓'),
                                      ),
                                    ],
                                  ],
                                  onChanged:
                                      (value) => _change(
                                        _query.copy(sort: value!, page: 1),
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selected.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                          child: Wrap(
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('Выбрано: ${_selected.length}'),
                              TextButton(
                                onPressed:
                                    _busy
                                        ? null
                                        : () => _mutate(
                                          _state.result!.items
                                              .where(
                                                (r) => _selected.contains(r.id),
                                              )
                                              .toList(),
                                          _query.archive == 'archived'
                                              ? 'restore'
                                              : 'archive',
                                        ),
                                child: Text(
                                  _query.archive == 'archived'
                                      ? 'Восстановить'
                                      : 'В архив',
                                ),
                              ),
                              if (role == Role.admin &&
                                  _query.archive == 'archived')
                                TextButton(
                                  onPressed:
                                      _busy
                                          ? null
                                          : () => _mutate(
                                            _state.result!.items
                                                .where(
                                                  (r) =>
                                                      _selected.contains(r.id),
                                                )
                                                .toList(),
                                            'delete',
                                          ),
                                  child: const Text('Удалить навсегда'),
                                ),
                              TextButton(
                                onPressed: () => setState(_selected.clear),
                                child: const Text('Снять выбор'),
                              ),
                            ],
                          ),
                        ),
                      if (_state.loading)
                        const LoadingState()
                      else if (_state.error != null)
                        ErrorState(
                          _state.error!.message,
                          () => _state.load(_query),
                        )
                      else if (_state.result?.items.isEmpty ?? true)
                        EmptyState(
                          onAction:
                              _query.parameters.isNotEmpty
                                  ? () => _change(const ListQuery())
                                  : spec.canWrite(role)
                                  ? () => context.go('/data/${spec.key}/new')
                                  : () => _state.load(_query),
                          action:
                              _query.parameters.isNotEmpty
                                  ? 'Сбросить фильтры'
                                  : spec.canWrite(role)
                                  ? 'Добавить запись'
                                  : 'Обновить',
                        )
                      else
                        LayoutBuilder(
                          builder:
                              (context, box) =>
                                  box.maxWidth < 760
                                      ? _cards(role)
                                      : _table(role, box.maxWidth),
                        ),
                      if (!_state.loading && _state.result != null)
                        _pagination(),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _filterField(FieldSpec f) {
    final selected = _query.filters[f.key] ?? '';
    if (f.kind == FieldKind.choice || f.kind == FieldKind.relation) {
      final options =
          f.kind == FieldKind.choice
              ? {...f.options}
              : {for (final r in _options[f.key] ?? <Record>[]) r.id: r.label};
      if (selected.isNotEmpty && !options.containsKey(selected)) {
        options[selected] = selected;
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('${widget.spec.key}:${f.key}:$selected'),
        value: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: f.label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Все')),
          for (final item in options.entries)
            DropdownMenuItem(
              value: item.key,
              child: Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => _filter(f.key, value!),
      );
    }
    return TextFormField(
      key: ValueKey('${widget.spec.key}:${f.key}:$selected'),
      initialValue: selected,
      decoration: InputDecoration(
        labelText: f.label,
        suffixIcon: const Icon(Icons.keyboard_return, size: 16),
      ),
      onFieldSubmitted: (value) => _filter(f.key, value.trim()),
    );
  }

  Widget _table(Role role, double width) {
    final spec = widget.spec;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: DataTable(
          showCheckboxColumn: role != Role.client && spec.canEdit(role),
          columns: [
            for (final key in spec.columns)
              DataColumn(label: Text(spec.label(key))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final record in _state.result!.items)
              DataRow(
                selected: _selected.contains(record.id),
                onSelectChanged:
                    role != Role.client && spec.canEdit(role)
                        ? (value) => setState(() {
                          value == true
                              ? _selected.add(record.id)
                              : _selected.remove(record.id);
                        })
                        : null,
                cells: [
                  for (final key in spec.columns)
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 210),
                        child: valueWidget(spec, record, key),
                      ),
                      onTap: () => context.go('/data/${spec.key}/${record.id}'),
                    ),
                  DataCell(_menu(record, role)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cards(Role role) => Column(
    children: [
      for (final record in _state.result!.items)
        InkWell(
          onTap: () => context.go('/data/${widget.spec.key}/${record.id}'),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (role != Role.client && widget.spec.canEdit(role))
                      Checkbox(
                        value: _selected.contains(record.id),
                        onChanged:
                            (value) => setState(() {
                              value == true
                                  ? _selected.add(record.id)
                                  : _selected.remove(record.id);
                            }),
                      ),
                    Expanded(
                      child: Text(
                        record.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _menu(record, role),
                  ],
                ),
                for (final key in widget.spec.columns.skip(1).take(4))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 104,
                          child: Text(
                            widget.spec.label(key),
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                        Expanded(child: valueWidget(widget.spec, record, key)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _menu(Record record, Role role) => PopupMenuButton<String>(
    tooltip: 'Действия',
    enabled: !_busy,
    onSelected: (action) {
      if (action == 'view' || action == 'edit') {
        context.go(
          '/data/${widget.spec.key}/${record.id}${action == 'edit' ? '/edit' : ''}',
        );
      } else {
        _mutate([record], action);
      }
    },
    itemBuilder:
        (_) => [
          const PopupMenuItem(value: 'view', child: Text('Открыть')),
          if (widget.spec.canEdit(role))
            const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
          if (role != Role.client && widget.spec.canEdit(role))
            PopupMenuItem(
              value: record.archived ? 'restore' : 'archive',
              child: Text(record.archived ? 'Восстановить' : 'В архив'),
            ),
          if (role == Role.admin && record.archived)
            const PopupMenuItem(
              value: 'delete',
              child: Text('Удалить навсегда'),
            ),
        ],
  );
  Widget _pagination() {
    final page = _state.result!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Страница ${page.page} из ${page.totalPages == 0 ? 1 : page.totalPages}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          IconButton(
            tooltip: 'Предыдущая страница',
            onPressed:
                page.page > 1
                    ? () => _change(_query.copy(page: page.page - 1))
                    : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Следующая страница',
            onPressed:
                page.page < page.totalPages
                    ? () => _change(_query.copy(page: page.page + 1))
                    : null,
            icon: const Icon(Icons.chevron_right),
          ),
          DropdownButton<int>(
            value: _query.size,
            underline: const SizedBox.shrink(),
            items: [
              for (final n in [10, 20, 50])
                DropdownMenuItem(
                  value: n,
                  child: Text('По $n', style: const TextStyle(fontSize: 12)),
                ),
            ],
            onChanged: (value) => _change(_query.copy(size: value, page: 1)),
          ),
        ],
      ),
    );
  }
}
