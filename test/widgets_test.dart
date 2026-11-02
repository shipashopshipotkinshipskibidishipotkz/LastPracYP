import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoservice_web/app.dart';
import 'package:autoservice_web/core/api.dart';
import 'package:autoservice_web/models/catalog.dart';
import 'package:autoservice_web/models/record.dart';
import 'package:autoservice_web/repositories/repository.dart';
import 'package:autoservice_web/state/auth_state.dart';

class FakeRepository implements Repository {
  bool fail = false, empty = false;
  int writes = 0;
  Completer<RecordPage>? pending;
  final record = const Record({
    'id': 'order000000001',
    'number': 'ЗН-1001',
    'status': 'scheduled',
    'starts_at': '2026-11-02 09:00:00Z',
    'ends_at': '2026-11-02 10:00:00Z',
    'total': 1620,
    'complaint': 'Плановое ТО',
    'services': ['service1'],
    'expand': {
      'vehicle': {
        'id': 'vehicle1',
        'brand': 'Toyota',
        'model': 'Camry',
        'plate': 'А123ВС777',
      },
    },
  });
  @override
  Future<RecordPage> list(
    EntitySpec spec,
    ListQuery query, {
    CancelToken? cancel,
  }) async {
    if (pending != null) return pending!.future;
    if (fail) throw const ApiFailure('Нет связи с сервером');
    return RecordPage(
      empty
          ? []
          : spec.key == 'orders'
          ? [record]
          : [],
      1,
      empty ? 0 : 1,
      1,
    );
  }

  @override
  Future<Record> get(EntitySpec spec, String id) async => record;
  @override
  Future<List<Record>> options(
    String collection, {
    Map<String, String> filters = const {},
  }) async => collection == 'orders' && !empty ? [record] : [];
  @override
  Future<Record> save(
    EntitySpec spec,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    writes++;
    return record;
  }

  @override
  Future<void> archive(EntitySpec spec, String id, bool archived) async {
    writes++;
  }

  @override
  Future<void> delete(EntitySpec spec, String id) async {
    writes++;
  }
}

Future<void> withApp(
  WidgetTester tester,
  String route,
  FakeRepository repo,
  Future<void> Function() run, {
  Role role = Role.admin,
  double width = 1280,
  bool settle = true,
  bool restoring = false,
  bool signedIn = true,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  SharedPreferences.setMockInitialValues({});
  final auth =
      AuthState(
          await SharedPreferences.getInstance(),
          'https://autoritm.example',
        )
        ..loading = restoring
        ..user =
            signedIn
                ? Record({
                  'id': 'user00000000001',
                  'name': 'Тестовый пользователь',
                  'email': 'user@example.com',
                  'role': role.name,
                })
                : null;
  try {
    await tester.pumpWidget(
      AutoritmApp(auth: auth, repository: repo, initialLocation: route),
    );
    if (restoring) {
      await tester.pump();
      auth.loading = false;
      auth.notifyListeners();
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    await run();
  } finally {
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  testWidgets(
    'restored client session still checks the requested admin route',
    (tester) async {
      await withApp(
        tester,
        '/admin',
        FakeRepository(),
        () async {
          expect(find.text('Доступ закрыт'), findsOneWidget);
          expect(find.text('Управление сервисом'), findsNothing);
        },
        role: Role.client,
        restoring: true,
      );
    },
  );
  testWidgets('an unauthenticated restored route leads to login', (
    tester,
  ) async {
    await withApp(
      tester,
      '/admin',
      FakeRepository(),
      () async {
        expect(find.text('С возвращением'), findsOneWidget);
        expect(find.text('Управление сервисом'), findsNothing);
      },
      restoring: true,
      signedIn: false,
    );
  });
  testWidgets('list displays a loading indicator while awaiting the API', (
    tester,
  ) async {
    final repo = FakeRepository()..pending = Completer<RecordPage>();
    await withApp(tester, '/data/orders', repo, () async {
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }, settle: false);
  });
  testWidgets('empty results have a clear create action', (tester) async {
    await withApp(
      tester,
      '/data/orders',
      FakeRepository()..empty = true,
      () async {
        expect(find.text('Пока ничего нет'), findsOneWidget);
        expect(find.text('Добавить запись'), findsOneWidget);
      },
    );
  });
  testWidgets('network error retry recovers to data', (tester) async {
    final repo = FakeRepository()..fail = true;
    await withApp(tester, '/data/orders', repo, () async {
      expect(find.text('Нет связи с сервером'), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('ЗН-1001'), findsOneWidget);
    });
  });
  testWidgets('form shows field errors and never submits invalid data', (
    tester,
  ) async {
    final repo = FakeRepository();
    await withApp(tester, '/data/categories/new', repo, () async {
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Обязательное поле'), findsOneWidget);
      expect(repo.writes, 0);
    });
  });
  testWidgets('client navigation hides staff sections and mutation buttons', (
    tester,
  ) async {
    await withApp(
      tester,
      '/data/services',
      FakeRepository()..empty = true,
      () async {
        expect(find.text('Управление'), findsNothing);
        expect(find.text('Рабочий день'), findsNothing);
        expect(find.text('Добавить'), findsNothing);
        expect(find.text('Мой гараж'), findsOneWidget);
      },
      role: Role.client,
    );
  });
  testWidgets('forbidden direct route shows an access-denied screen', (
    tester,
  ) async {
    await withApp(tester, '/admin', FakeRepository(), () async {
      expect(find.text('Доступ закрыт'), findsOneWidget);
      expect(find.text('Сотрудники и доступ'), findsNothing);
    }, role: Role.client);
  });
  for (final width in [360.0, 768.0, 1280.0, 1920.0]) {
    testWidgets('main screens fit a ${width.toInt()}px viewport', (
      tester,
    ) async {
      for (final route in [
        '/',
        '/data/orders',
        '/data/categories/new',
        '/workshop',
        '/schedule',
        '/garage',
      ]) {
        await withApp(
          tester,
          route,
          FakeRepository(),
          () async {
            expect(tester.takeException(), isNull, reason: route);
          },
          width: width,
          role:
              route == '/garage'
                  ? Role.client
                  : ['/workshop', '/schedule'].contains(route)
                  ? Role.master
                  : Role.admin,
        );
      }
    });
  }
}
