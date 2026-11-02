import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

class ApiFailure implements Exception {
  final String message;
  final int? status;
  final Map<String, String> fields;
  const ApiFailure(this.message, {this.status, this.fields = const {}});
  factory ApiFailure.fromDio(DioException error) {
    final code = error.response?.statusCode;
    final body = error.response?.data;
    final fields = <String, String>{};
    if (body is Map &&
        ['user_already_exists', 'email_exists'].contains(body['code'])) {
      fields['email'] = 'Этот email уже зарегистрирован';
    }
    if (body is Map && body['details'] is String) {
      try {
        final details = jsonDecode(body['details'] as String);
        if (details is Map) {
          details.forEach((key, value) => fields['$key'] = '$value');
        }
      } on FormatException {
        /* PostgreSQL may also return plain-text details. */
      }
    }
    if (body is Map && body['data'] is Map) {
      (body['data'] as Map).forEach((key, value) {
        if (value is Map) {
          fields['$key'] = '${value['message'] ?? 'Проверьте значение'}';
        }
      });
    }
    final message = switch (code) {
      401 => 'Сессия завершена. Войдите снова.',
      403 => 'Недостаточно прав для этого действия.',
      404 => 'Запись не найдена или недоступна.',
      409 =>
        body is Map
            ? '${body['message']}'
            : 'Запись изменилась или конфликтует с существующей.',
      422 =>
        fields.isEmpty && body is Map && body['message'] != null
            ? '${body['message']}'
            : 'Проверьте отмеченные поля.',
      429 => 'Слишком много попыток. Подождите немного и повторите.',
      400 =>
        fields.isEmpty
            ? 'Не удалось выполнить запрос. Проверьте данные.'
            : 'Проверьте отмеченные поля.',
      _ => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType
            .sendTimeout => 'Сервер не ответил вовремя. Повторите попытку.',
        DioExceptionType.connectionError || DioExceptionType.unknown =>
          'Нет связи с сервером. Проверьте подключение к интернету.',
        _ => 'Не удалось загрузить данные. Повторите попытку.',
      },
    };
    return ApiFailure(message, status: code, fields: fields);
  }
  @override
  String toString() => message;
}

String configuredBaseUrl() {
  const configured = String.fromEnvironment('SUPABASE_URL');
  return configured.replaceFirst(RegExp(r'/$'), '');
}

const publicApiKey = String.fromEnvironment('SUPABASE_ANON_KEY');

class ApiClient {
  final Dio dio;
  String? Function()? token;
  Future<bool> Function()? refresh;
  Future<bool>? _refreshing;
  ApiClient(String baseUrl, {String apiKey = '', Dio? transport})
    : dio = transport ?? Dio() {
    dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'apikey': apiKey},
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final value = token?.call();
          if (value != null && value.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $value';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          if (error.response?.statusCode == 401 &&
              request.extra['refreshed'] != true &&
              refresh != null) {
            _refreshing ??= refresh!();
            bool success;
            try {
              success = await _refreshing!;
            } finally {
              _refreshing = null;
            }
            if (success) {
              request.extra['refreshed'] = true;
              request.headers['Authorization'] = 'Bearer ${token?.call()}';
              try {
                handler.resolve(await dio.fetch<dynamic>(request));
                return;
              } on DioException catch (e) {
                handler.next(e);
                return;
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    CancelToken? cancel,
    bool safeRead = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await dio.request<dynamic>(
          path,
          data: data,
          queryParameters: query,
          cancelToken: cancel,
          options: Options(method: method),
        );
        return response.data;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        final transient =
            e.response == null || (e.response?.statusCode ?? 0) >= 500;
        if ((method == 'GET' || safeRead) && transient && attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
          continue;
        }
        throw ApiFailure.fromDio(e);
      }
    }
  }
}
