import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoservice_web/core/api.dart';
import 'package:autoservice_web/models/catalog.dart';
import 'package:autoservice_web/repositories/repository.dart';

class MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions request) handler;
  MockAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody reply(int status, Map<String, dynamic> data) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
ApiClient client(Future<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = MockAdapter(handler);
  return ApiClient('https://autoritm.example', transport: dio);
}

void main() {
  test(
    'repository sends structured server search, sorting and pagination',
    () async {
      final api = client((request) async {
        expect(request.path, '/rest/v1/rpc/list_records');
        final args = request.data as Map;
        expect(args['p_collection'], 'orders');
        expect(args['p_query']['size'], 20);
        expect(args['p_query']['page'], 2);
        expect(args['p_query']['sort'], 'starts_at');
        expect(args['p_query']['filters'], {'status': 'ready'});
        return reply(200, {
          'items': [],
          'page': 2,
          'totalPages': 2,
          'totalItems': 21,
        });
      });
      final result = await SupabaseRepository(api).list(
        entity('orders'),
        const ListQuery(
          page: 2,
          size: 20,
          sort: 'starts_at',
          filters: {'status': 'ready'},
        ),
      );
      expect(result.totalItems, 21);
      api.dio.close();
    },
  );
  test('422 server errors stay attached to their fields', () async {
    final api = client(
      (_) async => reply(422, {
        'code': 'PT422',
        'details': '{"vin":"VIN уже используется"}',
      }),
    );
    await expectLater(
      api.request('POST', '/records', data: {}),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.status, 'status', 422)
            .having(
              (e) => e.fields['vin'],
              'vin error',
              'VIN уже используется',
            ),
      ),
    );
    api.dio.close();
  });
  test('409 preserves the booking conflict explanation', () async {
    final api = client((_) async => reply(409, {'message': 'Пост занят'}));
    await expectLater(
      api.request('POST', '/records', data: {}),
      throwsA(
        isA<ApiFailure>().having((e) => e.message, 'message', 'Пост занят'),
      ),
    );
    api.dio.close();
  });
  test('GET retries an unavailable server and then exposes an error', () async {
    var calls = 0;
    final api = client((request) async {
      calls++;
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    });
    await expectLater(
      api.request('GET', '/records'),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 3);
    api.dio.close();
  });
  test('writes are never repeated automatically', () async {
    var calls = 0;
    final api = client((request) async {
      calls++;
      return reply(500, {});
    });
    await expectLater(
      api.request('POST', '/records', data: {'name': 'Масло'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 1);
    api.dio.close();
  });
  test(
    '401 refreshes the access token and repeats the original request once',
    () async {
      var calls = 0, refreshes = 0;
      var token = 'expired';
      final api = client((request) async {
        calls++;
        return request.headers['Authorization'] == 'Bearer fresh'
            ? reply(200, {'ok': true})
            : reply(401, {});
      });
      api.token = () => token;
      api.refresh = () async {
        refreshes++;
        token = 'fresh';
        return true;
      };
      expect(await api.request('GET', '/records'), {'ok': true});
      expect(calls, 2);
      expect(refreshes, 1);
      api.dio.close();
    },
  );
  test('a failed refresh does not loop', () async {
    var refreshes = 0;
    final api = client((_) async => reply(401, {}));
    api.refresh = () async {
      refreshes++;
      return false;
    };
    await expectLater(
      api.request('GET', '/records'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(refreshes, 1);
    api.dio.close();
  });
  test('timeouts have a distinct user-facing message', () {
    final error = ApiFailure.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/records'),
        type: DioExceptionType.receiveTimeout,
      ),
    );
    expect(error.message, contains('вовремя'));
  });
}
