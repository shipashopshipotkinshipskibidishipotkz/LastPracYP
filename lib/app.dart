import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'models/catalog.dart';
import 'models/record.dart';
import 'repositories/repository.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard.dart';
import 'screens/entity_detail.dart';
import 'screens/entity_form.dart';
import 'screens/entity_list.dart';
import 'screens/role_screens.dart';
import 'state/auth_state.dart';
import 'widgets/common.dart';
import 'widgets/workspace.dart';

String safeNext(String? input) {
  final uri = Uri.tryParse(input ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      ['/login', '/register', '/loading', '/forbidden'].contains(uri.path)) {
    return '/';
  }
  return uri.toString();
}

bool routeAllowed(Role role, Uri uri) {
  if (!canOpen(role, uri.path)) return false;
  if (uri.path.startsWith('/data/')) {
    final segments = uri.pathSegments;
    final spec = entity(segments[1]);
    if (segments.last == 'new' && !spec.canWrite(role)) return false;
    if (segments.last == 'edit' && !spec.canEdit(role)) return false;
  }
  return true;
}

class AutoritmApp extends StatefulWidget {
  final AuthState auth;
  final Repository repository;
  final String? initialLocation;
  const AutoritmApp({
    super.key,
    required this.auth,
    required this.repository,
    this.initialLocation,
  });
  @override
  State<AutoritmApp> createState() => _AutoritmAppState();
}

class _AutoritmAppState extends State<AutoritmApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.initialLocation,
    refreshListenable: widget.auth,
    redirect: (context, state) {
      final auth = widget.auth, path = state.uri.path;
      final authPage = path == '/login' || path == '/register';
      if (auth.loading) {
        return path == '/loading'
            ? null
            : '/loading?next=${Uri.encodeComponent(state.uri.toString())}';
      }
      final requested =
          path == '/loading'
              ? Uri.parse(safeNext(state.uri.queryParameters['next']))
              : state.uri;
      if (!auth.signedIn) {
        return authPage
            ? null
            : '/login?next=${Uri.encodeComponent(requested.toString())}';
      }
      if (authPage) {
        final next = safeNext(state.uri.queryParameters['next']);
        return routeAllowed(auth.role, Uri.parse(next)) ? next : '/forbidden';
      }
      if (!routeAllowed(auth.role, requested)) return '/forbidden';
      if (path == '/loading') return requested.toString();
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) => const Scaffold(body: LoadingState()),
      ),
      GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/register',
        builder: (_, _) => const AuthScreen(register: true),
      ),
      ShellRoute(
        builder: (_, _, child) => Workspace(child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
          GoRoute(path: '/garage', builder: (_, _) => const GarageScreen()),
          GoRoute(path: '/workshop', builder: (_, _) => const WorkshopScreen()),
          GoRoute(
            path: '/schedule',
            builder: (_, state) => ScheduleScreen(state.uri),
          ),
          GoRoute(
            path: '/booking',
            builder:
                (_, _) => EntityFormScreen(entity('orders'), booking: true),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/forbidden',
            builder:
                (context, _) => EmptyState(
                  title: 'Доступ закрыт',
                  message: 'Этот раздел недоступен вашей роли.',
                  icon: Icons.lock_outline,
                  action: 'На главную',
                  onAction: () => context.go('/'),
                ),
          ),
          GoRoute(
            path: '/data/:collection',
            builder:
                (_, state) => EntityListScreen(
                  entity(state.pathParameters['collection']!),
                  state.uri,
                  key: ValueKey(state.pathParameters['collection']),
                ),
          ),
          GoRoute(
            path: '/data/:collection/new',
            builder:
                (_, state) => EntityFormScreen(
                  entity(state.pathParameters['collection']!),
                ),
          ),
          GoRoute(
            path: '/data/:collection/:id/edit',
            builder:
                (_, state) => EntityFormScreen(
                  entity(state.pathParameters['collection']!),
                  id: state.pathParameters['id'],
                ),
          ),
          GoRoute(
            path: '/data/:collection/:id',
            builder:
                (_, state) => EntityDetailScreen(
                  entity(state.pathParameters['collection']!),
                  state.pathParameters['id']!,
                ),
          ),
        ],
      ),
    ],
    errorBuilder:
        (context, _) => Scaffold(
          body: EmptyState(
            title: 'Страница не найдена',
            message: 'Проверьте адрес или вернитесь к обзору.',
            action: 'На главную',
            onAction: () => context.go('/'),
          ),
        ),
  );
  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthState>.value(value: widget.auth),
      Provider<Repository>.value(value: widget.repository),
    ],
    child: MaterialApp.router(
      title: 'АвтоРитм · Автосервис',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      routerConfig: _router,
    ),
  );
}
