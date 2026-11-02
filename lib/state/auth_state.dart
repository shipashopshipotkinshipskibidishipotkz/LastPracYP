import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api.dart';
import '../models/record.dart';

class AuthState extends ChangeNotifier {
  static const storageKey = 'autoritm.supabase.session';
  final SharedPreferences preferences;
  final Dio _auth;
  Record? user;
  String? accessToken;
  String? _refreshToken;
  Timer? _timer;
  Future<bool>? _pendingRefresh;
  int _sessionVersion = 0;
  bool loading = true;
  Role get role => Role.parse(user?.text('role') ?? 'client');
  bool get signedIn => user != null;
  AuthState(
    this.preferences,
    String baseUrl, {
    String apiKey = '',
    Dio? transport,
  }) : _auth =
           transport ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               headers: {'apikey': apiKey, 'Content-Type': 'application/json'},
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );

  Future<void> restore() async {
    try {
      final stored = preferences.getString(storageKey);
      if (stored != null) {
        final session = jsonDecode(stored) as Map<String, dynamic>;
        _refreshToken = session['refresh_token'] as String?;
        await refresh();
      }
    } catch (_) {
      await preferences.remove(storageKey);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _accept(
    Map<String, dynamic> session, {
    required int version,
  }) async {
    if (version != _sessionVersion) return;
    accessToken = session['access_token'] as String;
    _refreshToken = session['refresh_token'] as String;
    final response = await _auth.get<dynamic>(
      '/rest/v1/users',
      queryParameters: {'id': 'eq.${session['user']['id']}', 'select': '*'},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final rows = response.data as List;
    if (version != _sessionVersion) return;
    if (rows.isEmpty || rows.first['deleted_at'] != null) {
      await logout();
      throw const ApiFailure(
        'Учётная запись отключена. Обратитесь к администратору.',
      );
    }
    user = Record(Map<String, dynamic>.from(rows.first));
    await preferences.setString(
      storageKey,
      jsonEncode({'refresh_token': _refreshToken}),
    );
    final expires = (session['expires_in'] as num?)?.toInt() ?? 3600;
    _timer?.cancel();
    _timer = Timer(
      Duration(seconds: (expires - 120).clamp(30, 86400)),
      refresh,
    );
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final version = ++_sessionVersion;
    try {
      final response = await _auth.post<dynamic>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email, 'password': password},
      );
      await _accept(Map<String, dynamic>.from(response.data), version: version);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        throw const ApiFailure(
          'Неверный email или пароль, либо email ещё не подтверждён.',
        );
      }
      throw ApiFailure.fromDio(e);
    }
  }

  Future<bool> register(String name, String email, String password) async {
    final version = ++_sessionVersion;
    try {
      final response = await _auth.post<dynamic>(
        '/auth/v1/signup',
        data: {
          'email': email,
          'password': password,
          'data': {'name': name},
        },
      );
      final data = Map<String, dynamic>.from(response.data);
      if (data['access_token'] == null) return false;
      await _accept(data, version: version);
      return true;
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  Future<bool> refresh() =>
      _pendingRefresh ??= _refreshSession().whenComplete(
        () => _pendingRefresh = null,
      );

  Future<bool> _refreshSession() async {
    if (_refreshToken == null) return false;
    final version = _sessionVersion;
    try {
      final response = await _auth.post<dynamic>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'refresh_token'},
        data: {'refresh_token': _refreshToken},
      );
      await _accept(Map<String, dynamic>.from(response.data), version: version);
      return version == _sessionVersion && signedIn;
    } on DioException catch (e) {
      if ([400, 401, 403].contains(e.response?.statusCode)) await logout();
      return false;
    } on ApiFailure {
      return false;
    }
  }

  Future<void> logout() async {
    _sessionVersion++;
    final oldToken = accessToken;
    _timer?.cancel();
    user = null;
    accessToken = null;
    _refreshToken = null;
    await preferences.remove(storageKey);
    notifyListeners();
    if (oldToken != null) {
      try {
        await _auth.post<dynamic>(
          '/auth/v1/logout',
          options: Options(headers: {'Authorization': 'Bearer $oldToken'}),
        );
      } on DioException {
        /* Local credentials are already removed. */
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth.close();
    super.dispose();
  }
}
