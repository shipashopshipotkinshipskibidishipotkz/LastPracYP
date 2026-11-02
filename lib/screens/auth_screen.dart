import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../state/auth_state.dart';
import '../widgets/workspace.dart';

class AuthScreen extends StatefulWidget {
  final bool register;
  const AuthScreen({super.key, this.register = false});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false, _visible = false;
  String? _error, _notice;
  Map<String, String> _fields = {};
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _notice = null;
      _fields = {};
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = context.read<AuthState>();
      if (widget.register) {
        final entered = await auth.register(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
        if (!entered && mounted) {
          setState(() {
            _busy = false;
            _notice =
                'Кабинет создан. Подтвердите email по ссылке в письме, затем войдите.';
          });
        }
      } else {
        await auth.login(_email.text.trim(), _password.text);
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          _fields = e.fields;
        });
        _form.currentState!.validate();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder:
            (context, box) => Row(
              children: [
                if (box.maxWidth >= 1000)
                  Expanded(
                    child: Container(
                      color: ink,
                      padding: const EdgeInsets.all(56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Brand(dark: true),
                          const Spacer(),
                          const Icon(
                            Icons.home_repair_service_outlined,
                            color: Color(0xFFF89570),
                            size: 76,
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Хороший сервис\nначинается с порядка.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Автомобили, записи и заказ-наряды —\nв одном рабочем пространстве.',
                            style: TextStyle(
                              color: Color(0xFFB4C1CF),
                              fontSize: 17,
                              height: 1.7,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'АВТОРИТМ  /  АВТОСЕРВИС',
                            style: TextStyle(
                              color: Color(0xFF8194A9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(box.maxWidth < 600 ? 24 : 48),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 410),
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (box.maxWidth < 1000) ...[
                                const Brand(),
                                const SizedBox(height: 42),
                              ],
                              Text(
                                widget.register
                                    ? 'Добро пожаловать'
                                    : 'С возвращением',
                                style:
                                    Theme.of(context).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.register
                                    ? 'Создайте личный кабинет для записи на обслуживание.'
                                    : 'Войдите, чтобы продолжить работу.',
                                style: const TextStyle(color: muted),
                              ),
                              const SizedBox(height: 32),
                              if (widget.register) ...[
                                TextFormField(
                                  controller: _name,
                                  enabled: !_busy,
                                  decoration: const InputDecoration(
                                    labelText: 'Ваше имя',
                                  ),
                                  validator:
                                      (v) =>
                                          _fields['name'] ??
                                          validate(
                                            const FieldSpec(
                                              'name',
                                              'Имя',
                                              maxLength: 100,
                                            ),
                                            v,
                                          ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              TextFormField(
                                controller: _email,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                ),
                                validator:
                                    (v) =>
                                        _fields['email'] ??
                                        validate(
                                          const FieldSpec(
                                            'email',
                                            'Email',
                                            kind: FieldKind.email,
                                          ),
                                          v,
                                        ),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _password,
                                enabled: !_busy,
                                obscureText: !_visible,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Пароль',
                                  suffixIcon: IconButton(
                                    tooltip:
                                        _visible
                                            ? 'Скрыть пароль'
                                            : 'Показать пароль',
                                    onPressed:
                                        () => setState(
                                          () => _visible = !_visible,
                                        ),
                                    icon: Icon(
                                      _visible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                validator:
                                    (v) =>
                                        _fields['password'] ??
                                        validate(
                                          const FieldSpec(
                                            'password',
                                            'Пароль',
                                            kind: FieldKind.password,
                                            maxLength: 72,
                                          ),
                                          v,
                                        ),
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              if (widget.register) ...[
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _confirm,
                                  enabled: !_busy,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Повторите пароль',
                                  ),
                                  validator:
                                      (value) =>
                                          value == _password.text
                                              ? null
                                              : 'Пароли не совпадают',
                                ),
                              ],
                              if (_notice != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 18),
                                  child: Text(
                                    _notice!,
                                    style: const TextStyle(
                                      color: Color(0xFF24805C),
                                    ),
                                  ),
                                ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 18),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _busy ? null : _submit,
                                  child: Text(
                                    _busy
                                        ? 'Подождите…'
                                        : widget.register
                                        ? 'Создать кабинет'
                                        : 'Войти',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Center(
                                child: TextButton(
                                  onPressed:
                                      _busy
                                          ? null
                                          : () => context.go(
                                            widget.register
                                                ? '/login'
                                                : '/register',
                                          ),
                                  child: Text(
                                    widget.register
                                        ? 'Уже есть аккаунт? Войти'
                                        : 'Нет аккаунта? Зарегистрироваться',
                                  ),
                                ),
                              ),
                              if (!widget.register) ...[
                                const SizedBox(height: 24),
                                const Divider(),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Демонстрационные аккаунты',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  children: [
                                    for (final demo in [
                                      ('admin', 'Администратор', 'Admin12345!'),
                                      ('master', 'Мастер', 'Master12345!'),
                                      ('client', 'Клиент', 'Client12345!'),
                                    ])
                                      ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(demo.$2),
                                        subtitle: Text(
                                          '${demo.$1}@autoritm.local',
                                        ),
                                        trailing: const Icon(
                                          Icons.arrow_outward,
                                          size: 18,
                                        ),
                                        onTap:
                                            _busy
                                                ? null
                                                : () => setState(() {
                                                  _email.text =
                                                      '${demo.$1}@autoritm.local';
                                                  _password.text = demo.$3;
                                                }),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      ),
    ),
  );
}
