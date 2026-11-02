import 'package:dio/dio.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../models/catalog.dart';
import '../models/record.dart';

class ListQuery {
  final String search, sort, archive;
  final int page, size;
  final Map<String, String> filters;
  const ListQuery({
    this.search = '',
    this.sort = '-created',
    this.archive = 'active',
    this.page = 1,
    this.size = 10,
    this.filters = const {},
  });
  factory ListQuery.fromUri(Uri uri) {
    final p = uri.queryParameters;
    return ListQuery(
      search: p['q'] ?? '',
      sort: p['sort'] ?? '-created',
      archive:
          ['active', 'archived', 'all'].contains(p['archive'])
              ? p['archive']!
              : 'active',
      page: (int.tryParse(p['page'] ?? '') ?? 1).clamp(1, 100000),
      size:
          [10, 20, 50].contains(int.tryParse(p['size'] ?? ''))
              ? int.parse(p['size']!)
              : 10,
      filters: Map.fromEntries(
        p.entries
            .where((e) => e.key.startsWith('f.'))
            .map((e) => MapEntry(e.key.substring(2), e.value)),
      ),
    );
  }
  Map<String, String> get parameters => {
    if (search.isNotEmpty) 'q': search,
    if (sort != '-created') 'sort': sort,
    if (archive != 'active') 'archive': archive,
    if (page > 1) 'page': '$page',
    if (size != 10) 'size': '$size',
    for (final f in filters.entries)
      if (f.value.isNotEmpty) 'f.${f.key}': f.value,
  };
  ListQuery copy({
    String? search,
    String? sort,
    String? archive,
    int? page,
    int? size,
    Map<String, String>? filters,
  }) => ListQuery(
    search: search ?? this.search,
    sort: sort ?? this.sort,
    archive: archive ?? this.archive,
    page: page ?? this.page,
    size: size ?? this.size,
    filters: filters ?? this.filters,
  );
  String safeSort(EntitySpec spec) {
    final key = sort.startsWith('-') ? sort.substring(1) : sort;
    return {
          ...spec.columns,
          ...spec.fields.map((f) => f.key),
          'created',
          'updated',
        }.contains(key)
        ? sort
        : '-created';
  }

  Map<String, dynamic> payload(EntitySpec spec) {
    final allowed = {...spec.fields.map((f) => f.key), 'from', 'to'};
    final values = <String, String>{};
    for (final entry in filters.entries) {
      if (!allowed.contains(entry.key) || entry.value.isEmpty) continue;
      var value = entry.value;
      if (entry.key == 'from' || entry.key == 'to') {
        if (DateTime.tryParse(value) == null) continue;
        if (value.length == 10) {
          value = apiDate(
            DateTime.parse(
              '${value}T${entry.key == 'from' ? '00:00:00' : '23:59:59'}',
            ),
          );
        }
      }
      values[entry.key] = value;
    }
    return {
      'search': search,
      'sort': safeSort(spec),
      'archive': archive,
      'page': page,
      'size': size,
      'filters': values,
    };
  }
}

abstract interface class Repository {
  Future<RecordPage> list(
    EntitySpec spec,
    ListQuery query, {
    CancelToken? cancel,
  });
  Future<Record> get(EntitySpec spec, String id);
  Future<Record> save(EntitySpec spec, Map<String, dynamic> data, {String? id});
  Future<void> archive(EntitySpec spec, String id, bool archived);
  Future<void> delete(EntitySpec spec, String id);
  Future<List<Record>> options(
    String collection, {
    Map<String, String> filters = const {},
  });
}

class SupabaseRepository implements Repository {
  final ApiClient api;
  SupabaseRepository(this.api);
  Future<dynamic> _rpc(
    String method,
    Map<String, dynamic> args, {
    CancelToken? cancel,
    bool read = false,
  }) => api.request(
    'POST',
    '/rest/v1/rpc/$method',
    data: args,
    cancel: cancel,
    safeRead: read,
  );
  @override
  Future<RecordPage> list(
    EntitySpec spec,
    ListQuery query, {
    CancelToken? cancel,
  }) async => RecordPage.fromJson(
    Map<String, dynamic>.from(
      await _rpc(
        'list_records',
        {'p_collection': spec.key, 'p_query': query.payload(spec)},
        cancel: cancel,
        read: true,
      ),
    ),
  );
  @override
  Future<Record> get(EntitySpec spec, String id) async => Record(
    Map<String, dynamic>.from(
      await _rpc('get_record', {
        'p_collection': spec.key,
        'p_id': id,
      }, read: true),
    ),
  );
  @override
  Future<Record> save(
    EntitySpec spec,
    Map<String, dynamic> data, {
    String? id,
  }) async => Record(
    Map<String, dynamic>.from(
      await _rpc(spec.key == 'users' ? 'manage_account' : 'save_record', {
        if (spec.key != 'users') 'p_collection': spec.key,
        'p_id': id,
        'p_data': data,
      }),
    ),
  );
  @override
  Future<void> archive(EntitySpec spec, String id, bool archived) async {
    await save(spec, {
      'deleted_at': archived ? DateTime.now().toUtc().toIso8601String() : null,
    }, id: id);
  }

  @override
  Future<void> delete(EntitySpec spec, String id) async {
    await _rpc('delete_record', {'p_collection': spec.key, 'p_id': id});
  }

  @override
  Future<List<Record>> options(
    String collection, {
    Map<String, String> filters = const {},
  }) async {
    final spec = entity(collection), items = <Record>[];
    var page = 1;
    while (true) {
      final result = await list(
        spec,
        ListQuery(size: 200, page: page, filters: filters),
      );
      items.addAll(result.items);
      if (page >= result.totalPages) break;
      page++;
    }
    return items;
  }
}
