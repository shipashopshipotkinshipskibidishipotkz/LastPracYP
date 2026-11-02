import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoservice_web/models/record.dart';
import 'package:autoservice_web/state/auth_state.dart';

class AuthAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  AuthAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody response(int code, dynamic data) => ResponseBody.fromString(
  jsonEncode(data),
  code,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
const session = {
  'access_token': 'new-access',
  'refresh_token': 'new-refresh',
  'expires_in': 3600,
  'user': {'id': 'user-id'},
};
const profile = {
  'id': 'user-id',
  'role': 'client',
  'name': 'Клиент',
  'email': 'client@example.com',
  'deleted_at': null,
};
Future<AuthState> setup(
  Future<ResponseBody> Function(RequestOptions) handler, {
  String? stored,
}) async {
  SharedPreferences.setMockInitialValues({
    if (stored != null) AuthState.storageKey: stored,
  });
  final transport = Dio(BaseOptions(baseUrl: 'https://autoritm.example'))
    ..httpClientAdapter = AuthAdapter(handler);
  return AuthState(
    await SharedPreferences.getInstance(),
    'https://autoritm.example',
    transport: transport,
  );
}

void main() {
  test(
    'session restores with a rotated refresh token and a server role',
    () async {
      final auth = await setup((request) async {
        if (request.path == '/auth/v1/token') {
          expect(request.queryParameters['grant_type'], 'refresh_token');
          expect(request.data['refresh_token'], 'old-refresh');
          return response(200, session);
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        return response(200, [profile]);
      }, stored: '{"refresh_token":"old-refresh","role":"admin"}');
      try {
        await auth.restore();
        expect(auth.signedIn, true);
        expect(auth.role, Role.client);
        expect(
          auth.preferences.getString(AuthState.storageKey),
          '{"refresh_token":"new-refresh"}',
        );
      } finally {
        auth.dispose();
      }
    },
  );
  test('invalid refresh credential clears the saved session', () async {
    final auth = await setup(
      (_) async => response(400, {'error': 'invalid_grant'}),
      stored: '{"refresh_token":"expired"}',
    );
    try {
      await auth.restore();
      expect(auth.signedIn, false);
      expect(auth.preferences.getString(AuthState.storageKey), isNull);
      expect(auth.loading, false);
    } finally {
      auth.dispose();
    }
  });
  test('concurrent refresh requests share one token rotation', () async {
    var refreshes = 0;
    final auth = await setup((request) async {
      if (request.path == '/auth/v1/token') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return response(200, session);
      }
      return response(200, [profile]);
    }, stored: '{"refresh_token":"old-refresh"}');
    try {
      await auth.restore();
      refreshes = 0;
      expect(
        await Future.wait([auth.refresh(), auth.refresh(), auth.refresh()]),
        everyElement(true),
      );
      expect(refreshes, 1);
    } finally {
      auth.dispose();
    }
  });
  test(
    'registration handles email confirmation without a hanging spinner',
    () async {
      final auth = await setup((request) async {
        expect(request.path, '/auth/v1/signup');
        expect(request.data['data'], {'name': 'Клиент'});
        expect(request.data.containsKey('role'), false);
        return response(200, {
          'user': {'id': 'new-user'},
        });
      });
      try {
        expect(
          await auth.register('Клиент', 'client@example.com', 'Password12345!'),
          false,
        );
        expect(auth.signedIn, false);
      } finally {
        auth.dispose();
      }
    },
  );
  test(
    'a refresh completing after logout cannot sign the user back in',
    () async {
      final delayed = Completer<ResponseBody>();
      var delayProfile = false;
      final auth = await setup((request) async {
        if (request.path == '/auth/v1/token') return response(200, session);
        if (request.path == '/auth/v1/logout') return response(200, {});
        return delayProfile ? delayed.future : response(200, [profile]);
      }, stored: '{"refresh_token":"old-refresh"}');
      try {
        await auth.restore();
        delayProfile = true;
        final refreshing = auth.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await auth.logout();
        delayed.complete(response(200, [profile]));
        expect(await refreshing, false);
        expect(auth.signedIn, false);
        expect(auth.preferences.getString(AuthState.storageKey), isNull);
      } finally {
        auth.dispose();
      }
    },
  );
}
