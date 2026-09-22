import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPw = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _emailIsValid(String email) {
    if (email.trim().isEmpty) return true;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'O nome deve ter pelo menos 2 caracteres.');
      return;
    }
    if (_username.text.trim().length < 3) {
      setState(() => _error = 'O nome de usuário deve ter pelo menos 3 caracteres.');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_username.text.trim())) {
      setState(() => _error = 'O nome de usuário só pode conter letras, números e _');
      return;
    }
    if (!_emailIsValid(_email.text)) {
      setState(() => _error = 'E-mail inválido.');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Mínimo 8 caracteres.');
      return;
    }

    setState(() => _error = null);
    FocusManager.instance.primaryFocus?.unfocus();

    final locale = ref.read(localeProvider).locale?.languageCode ?? 'pt';

    final body = <String, dynamic>{
      'username': _username.text.trim(),
      'name': _name.text.trim(),
      'password': _password.text,
      'preferred_lang': locale,
    };
    if (_email.text.trim().isNotEmpty) body['email'] = _email.text.trim();

    try {
      await ref.read(authProvider.notifier).register(body);
      // Navegação após registo é tratada pelo redirect central do router.
    } catch (err) {
      final msg = err.toString().toLowerCase();
      setState(() {
        if (msg.contains('username already')) {
          _error = 'Este nome de usuário já está em uso.';
        } else if (msg.contains('email already')) {
          _error = 'Este e-mail já está cadastrado.';
        } else {
          _error = 'Falha ao criar conta. Tente novamente.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authProvider).loading;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: SvgPicture.asset('assets/icons/logo.svg', height: 48)),
                    const SizedBox(height: 20),
                    const Text('Criar conta',
                        style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Comece agora a assistir',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],
                    // SEM AutofillGroup / autofillHints — mesmo motivo do login.
                    const Text('Nome completo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.badge_outlined, size: 20), isDense: true),
                    ),
                    const SizedBox(height: 4),
                    const Text('Pode incluir nome e sobrenome, acentos, etc.',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(height: 13),
                    const Text('Nome de usuário', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const Text('Letras, números e _ (sem espaços)',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(height: 13),
                    Row(children: [
                      const Text('E-mail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      const Text('(opcional)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ]),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined, size: 20), isDense: true),
                    ),
                    const SizedBox(height: 13),
                    const Text('Senha', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _password,
                      obscureText: !_showPw,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _showPw = !_showPw),
                        ),
                      ),
                    ),
                    const Text('Mínimo 8 caracteres', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      onPressed: loading ? null : _submit,
                      child: loading
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Criar conta'),
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 14),
                    Center(
                      child: Wrap(alignment: WrapAlignment.center, children: [
                        const Text('Já tem conta? ', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        GestureDetector(
                          onTap: () => context.go('/auth/login'),
                          child: const Text('Entrar',
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
