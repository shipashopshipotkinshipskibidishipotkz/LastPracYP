import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/catalog.dart';

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class PageHeading extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: muted)),
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child:
            box.maxWidth < 600
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text,
                    if (action != null) ...[
                      const SizedBox(height: 16),
                      action!,
                    ],
                  ],
                )
                : Row(
                  children: [
                    Expanded(child: text),
                    if (action != null) ...[const SizedBox(width: 20), action!],
                  ],
                ),
      );
    },
  );
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'in_progress' => const Color(0xFF2764B0),
      'ready' || 'good' || 'closed' => const Color(0xFF24805C),
      'cancelled' || 'critical' => const Color(0xFFB03D3D),
      'scheduled' || 'attention' => const Color(0xFF9C6A17),
      _ => muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        statuses[status] ?? conditions[status] ?? status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final VoidCallback? onAction;
  final String action;
  final IconData icon;
  const EmptyState({
    super.key,
    this.title = 'Пока ничего нет',
    this.message = 'Измените условия поиска или добавьте первую запись.',
    this.onAction,
    this.action = 'Сбросить фильтры',
    this.icon = Icons.search_off_outlined,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: muted),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAction, child: Text(action)),
            ],
          ],
        ),
      ),
    ),
  );
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const ErrorState(this.message, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => EmptyState(
    title: 'Не удалось загрузить',
    message: message,
    icon: Icons.cloud_off_outlined,
    action: 'Повторить',
    onAction: retry,
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(64),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Подтвердить',
}) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
    ) ??
    false;

void notify(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
