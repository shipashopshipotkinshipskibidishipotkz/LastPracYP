import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api.dart';
import '../models/catalog.dart';
import '../models/record.dart';
import '../repositories/repository.dart';

class ListState extends ChangeNotifier {
  final Repository repository;
  final EntitySpec spec;
  RecordPage? result;
  ApiFailure? error;
  bool loading = false;
  CancelToken? _cancel;
  bool _disposed = false;
  ListState(this.repository, this.spec);
  Future<void> load(ListQuery query) async {
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await repository.list(spec, query, cancel: token);
      if (!_disposed && !token.isCancelled) result = page;
    } on ApiFailure catch (e) {
      if (!token.isCancelled) error = e;
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) error = ApiFailure.fromDio(e);
    } finally {
      if (!_disposed && !token.isCancelled) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
