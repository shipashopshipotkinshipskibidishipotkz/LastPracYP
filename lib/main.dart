import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/api.dart';
import 'repositories/repository.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final preferences = await SharedPreferences.getInstance();
  final baseUrl = configuredBaseUrl();
  if (baseUrl.isEmpty || publicApiKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Запустите start.ps1 для сборки с настройками Supabase из config.json.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  final auth = AuthState(preferences, baseUrl, apiKey: publicApiKey);
  final api = ApiClient(baseUrl, apiKey: publicApiKey)
    ..token = () => auth.accessToken;
  api.refresh = auth.refresh;
  runApp(AutoritmApp(auth: auth, repository: SupabaseRepository(api)));
  unawaited(auth.restore());
}
