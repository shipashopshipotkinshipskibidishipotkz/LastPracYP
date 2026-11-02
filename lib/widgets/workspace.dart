import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/record.dart';
import '../state/auth_state.dart';

class NavItem {
  final String label, path;
  final IconData icon;
  const NavItem(this.label, this.path, this.icon);
}

List<NavItem> navigation(Role role) => [
  const NavItem('Обзор', '/', Icons.space_dashboard_outlined),
  if (role == Role.master) ...[
    const NavItem('Рабочий день', '/workshop', Icons.construction_outlined),
    const NavItem('Расписание', '/schedule', Icons.calendar_month_outlined),
  ],
  if (role == Role.client) ...[
    const NavItem('Мой гараж', '/garage', Icons.garage_outlined),
    const NavItem('Записаться', '/booking', Icons.add_circle_outline),
  ],
  const NavItem('Заказ-наряды', '/data/orders', Icons.receipt_long_outlined),
  if (role != Role.client)
    const NavItem('Клиенты', '/data/customers', Icons.people_outline),
  const NavItem('Автомобили', '/data/vehicles', Icons.directions_car_outlined),
  const NavItem('Услуги', '/data/services', Icons.build_outlined),
  if (role != Role.client)
    const NavItem('Запчасти', '/data/parts', Icons.inventory_2_outlined),
  const NavItem('Диагностика', '/data/inspections', Icons.fact_check_outlined),
  if (role != Role.client)
    const NavItem(
      'Работы заказов',
      '/data/order_services',
      Icons.assignment_outlined,
    ),
  if (role != Role.client)
    const NavItem(
      'Материалы заказов',
      '/data/order_parts',
      Icons.handyman_outlined,
    ),
  if (role == Role.admin)
    const NavItem('Управление', '/admin', Icons.admin_panel_settings_outlined),
];

class Brand extends StatelessWidget {
  final bool dark;
  const Brand({super.key, this.dark = false});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 25),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'АвтоРитм',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: dark ? Colors.white : ink,
          ),
        ),
      ),
    ],
  );
}

class Workspace extends StatelessWidget {
  final Widget child;
  const Workspace(this.child, {super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final path = GoRouterState.of(context).uri.path;
    final items = navigation(auth.role);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final side = _sidebar(context, auth, items, path, wide);
    return Scaffold(
      drawer: wide ? null : Drawer(backgroundColor: ink, child: side),
      appBar:
          wide
              ? null
              : AppBar(
                title: const Brand(),
                actions: [
                  IconButton(
                    tooltip: 'Мой профиль',
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                ],
              ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              SizedBox(width: 244, child: ColoredBox(color: ink, child: side)),
            Expanded(
              child: Column(
                children: [
                  if (wide)
                    Container(
                      height: 72,
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.home_repair_service_outlined,
                            size: 18,
                            color: muted,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Автосервис / Рабочее пространство',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => context.go('/profile'),
                            icon: CircleAvatar(
                              radius: 16,
                              backgroundColor: canvas,
                              child: Text(
                                (auth.user?.text('name') ?? 'А').substring(
                                  0,
                                  1,
                                ),
                                style: const TextStyle(
                                  color: ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            label: Text(
                              auth.user?.text('name') ?? '',
                              style: const TextStyle(color: ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1540),
                        child: Padding(
                          padding: EdgeInsets.all(
                            MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(
    BuildContext context,
    AuthState auth,
    List<NavItem> items,
    String path,
    bool wide,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 26, 24, 8),
        child: Brand(dark: true),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        child: Text(
          auth.role.title,
          style: const TextStyle(color: Color(0xFF9AA9BA), fontSize: 12),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color:
                      path == item.path ||
                              (item.path != '/' &&
                                  path.startsWith('${item.path}/'))
                          ? const Color(0xFF2A3B4E)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: Icon(
                      item.icon,
                      size: 20,
                      color:
                          path == item.path
                              ? const Color(0xFFF89570)
                              : const Color(0xFFAAB7C7),
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        color:
                            path == item.path
                                ? Colors.white
                                : const Color(0xFFCCD5E0),
                        fontSize: 13,
                        fontWeight:
                            path == item.path
                                ? FontWeight.w700
                                : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      if (!wide) Navigator.pop(context);
                      context.go(item.path);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      const Divider(color: Color(0xFF2C3C4E), height: 1),
      ListTile(
        leading: const Icon(Icons.logout, color: Color(0xFFAAB7C7), size: 20),
        title: const Text(
          'Выйти',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
        ),
        onTap: () => auth.logout(),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 18),
        child: Text(
          'Сервис в вашем ритме',
          style: TextStyle(color: Color(0xFF8293A5), fontSize: 11),
        ),
      ),
    ],
  );
}
