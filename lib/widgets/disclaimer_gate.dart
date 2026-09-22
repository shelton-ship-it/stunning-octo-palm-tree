import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

/// disclaimer_gate.dart
///
/// FIX: em falta no mobile — o site mostra, uma vez por sessão depois do
/// login, um modal de aviso legal citando as políticas da plataforma
/// (Providers.tsx → DisclaimerGate + DisclaimerModal.tsx). O app não tinha
/// nenhum equivalente. Este widget replica fielmente o mesmo texto (já
/// existia em assets/i18n/*.json, chaves `disclaimer.*`) e o mesmo
/// comportamento de persistência:
///   - "Continuar" (accept) só esconde nesta sessão — não grava nada, por
///     isso volta a aparecer no próximo arranque da app (idêntico ao web:
///     onAccept só faz setShow(false), sem tocar em localStorage).
///   - "Ocultar" (dismiss) grava uma flag permanente
///     (SharedPreferences 'pixgo_disclaimer_dismissed', equivalente ao
///     localStorage do web) e nunca mais volta a aparecer.
class DisclaimerGate extends ConsumerStatefulWidget {
  final Widget child;
  const DisclaimerGate({super.key, required this.child});

  @override
  ConsumerState<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends ConsumerState<DisclaimerGate> {
  static const _prefsKey = 'pixgo_disclaimer_dismissed';

  bool _show = false;
  bool _checked = false;
  String? _lastCheckedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeCheck();
  }

  Future<void> _maybeCheck() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null || userId == _lastCheckedUserId) return;
    _lastCheckedUserId = userId;

    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_prefsKey) ?? false;
    if (!mounted) return;
    setState(() {
      _show = !dismissed;
      _checked = true;
    });
  }

  Future<void> _onDismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    if (mounted) setState(() => _show = false);
  }

  void _onAccept() => setState(() => _show = false);

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).user?.id;
    // Se o utilizador mudar (ex: logout + login com outra conta), reavalia.
    if (userId != null && userId != _lastCheckedUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheck());
    }

    return Stack(children: [
      widget.child,
      if (_checked && _show) _DisclaimerModal(onAccept: _onAccept, onDismiss: _onDismiss),
    ]);
  }
}

class _DisclaimerModal extends StatelessWidget {
  final VoidCallback onAccept;
  final Future<void> Function() onDismiss;
  const _DisclaimerModal({required this.onAccept, required this.onDismiss});

  Widget _section(BuildContext context, String titleKey, String bodyKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('disclaimer.$titleKey'),
            style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textTitle)),
        const SizedBox(height: 5),
        Text(context.t('disclaimer.$bodyKey'),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = context.t('disclaimer.email');
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.82),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 80, offset: const Offset(0, 24))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SvgPicture.asset('assets/icons/logo.svg', height: 28),
                      const SizedBox(height: 8),
                      Text(context.t('disclaimer.title'),
                          style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(context.t('disclaimer.subtitle'), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ),
                  // Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _section(context, 's1t', 's1'),
                        _section(context, 's2t', 's2'),
                        _section(context, 's3t', 's3'),
                        _section(context, 's4t', 's4'),
                        _section(context, 's5t', 's5'),
                        _section(context, 's6t', 's6'),
                        _section(context, 's7t', 's7'),
                        InkWell(
                          onTap: () => launchUrl(Uri.parse('mailto:$email')),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.06),
                              border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(email, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  ),
                  // Footer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                    child: Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onAccept,
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(context.t('disclaimer.accept')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onDismiss(),
                          icon: const Icon(Icons.block, size: 15),
                          label: Text(context.t('disclaimer.dismiss'), style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
