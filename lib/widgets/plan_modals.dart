import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/api_client.dart';

/// Ícones de pagamento por país — decidido pelo MESMO endpoint real que já
/// escolhe o gateway (GET /payments/gateway, api-core, decide pelo IP no
/// servidor). Chamado uma vez com um plano qualquer (o gateway não muda
/// por plano, só por país) só para saber M-Pesa (MZ/ZumboPay) vs
/// Pix/Visa/Mastercard/Boleto (resto, Hotmart). Pedido explícito do
/// utilizador — não existe no site real, adicionado só na app.
class PaymentBadgesRow extends StatefulWidget {
  final String label; // ex.: 'Pague com' ou 'Assine com'
  const PaymentBadgesRow({super.key, required this.label});
  @override
  State<PaymentBadgesRow> createState() => _PaymentBadgesRowState();
}

class _PaymentBadgesRowState extends State<PaymentBadgesRow> {
  String? _gateway;

  @override
  void initState() {
    super.initState();
    paymentsApi.gateway('monthly').then((r) {
      if (mounted) setState(() => _gateway = r['gateway']?.toString());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_gateway == null) return const SizedBox.shrink();
    final isMpesa = _gateway == 'zumbopay';
    final icons = isMpesa
        ? ['assets/icons/payments/mpesa.svg']
        : ['assets/icons/payments/pix.svg', 'assets/icons/payments/visa.svg', 'assets/icons/payments/mastercard.svg', 'assets/icons/payments/boleto.svg'];
    final text = isMpesa ? '${widget.label} M-Pesa' : '${widget.label} Pix ou Visa';
    return Column(children: [
      Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        alignment: WrapAlignment.center,
        children: icons
            .map((p) => SizedBox(height: isMpesa ? 22 : 18, child: SvgPicture.asset(p)))
            .toList(),
      ),
    ]);
  }
}

/// RateLimitModal — porte de components/ui/RateLimitModal.tsx: aparece
/// quando o servidor devolve 429 (limite diário) no player VOD ou canais.
/// Preço/nome SEMPRE vindos de `plans` (o corpo do 429), nunca hardcoded.
class RateLimitModal extends StatelessWidget {
  final List<dynamic> plans;
  final String? message;
  const RateLimitModal({super.key, required this.plans, this.message});

  static Future<void> show(BuildContext context, {required List<dynamic> plans, String? message}) {
    return showDialog(context: context, barrierDismissible: true, builder: (_) => RateLimitModal(plans: plans, message: message));
  }

  @override
  Widget build(BuildContext context) {
    final paid = plans.map((e) => AppPlan.fromJson(e as Map<String, dynamic>)).where((p) => p.id != 'free').toList();
    final featured = paid.isNotEmpty ? paid.first : null;
    final others = paid.length > 1 ? paid.sublist(1) : <AppPlan>[];

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_clock_rounded, color: AppColors.primary, size: 34),
          const SizedBox(height: 12),
          const Text('Limite diário atingido', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            message ?? 'Assine um plano para continuar a assistir sem limites.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
          if (featured != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withOpacity(0.4))),
              child: Column(children: [
                Text(featured.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 4),
                Text('por apenas ${featured.label ?? ''}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...others.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(p.name, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    Text(p.label ?? '', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  ]),
                )),
          ],
          const SizedBox(height: 16),
          const PaymentBadgesRow(label: 'Assine com'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/main/plans${featured != null ? '?highlight=${featured.id}' : ''}');
              },
              child: const Text('Ver planos'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Agora não', style: TextStyle(color: AppColors.textMuted))),
        ]),
      ),
    );
  }
}

/// SessionReplacedModal — porte de components/ui/SessionReplacedModal.tsx:
/// 409, outro dispositivo assumiu a sessão (limite de telas do plano).
class SessionReplacedModal extends StatelessWidget {
  final String? message;
  const SessionReplacedModal({super.key, this.message});

  static Future<void> show(BuildContext context, {String? message}) {
    return showDialog(context: context, builder: (_) => SessionReplacedModal(message: message));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: const Text('Sessão encerrada'),
      content: Text(
        message ?? 'A sua sessão foi encerrada porque outro dispositivo começou a assistir.',
        style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    );
  }
}

/// PlansModal — porte de components/ui/PlansModal.tsx: no /catalog, só
/// plano free, 1×/dia (chave px_plans_modal_last_seen, mesma do site).
class PlansModalGate extends StatefulWidget {
  final Widget child;
  const PlansModalGate({super.key, required this.child});
  @override
  State<PlansModalGate> createState() => _PlansModalGateState();
}

class _PlansModalGateState extends State<PlansModalGate> {
  static const _kSeenKey = 'px_plans_modal_last_seen';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    // Só mostra para o plano free — quem chama isto (catalog_screen) já
    // filtra por isPremium antes de montar este gate; ver uso.
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(_kSeenKey) == today) return;
    await prefs.setString(_kSeenKey, today);

    List<dynamic> plans;
    try {
      plans = await paymentsApi.plans();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final paid = plans.map((e) => AppPlan.fromJson(e as Map<String, dynamic>)).where((p) => p.id != 'free').toList();
    if (paid.isEmpty) return;

    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.workspace_premium_rounded, color: AppColors.primary, size: 34),
            const SizedBox(height: 12),
            const Text('Continue no plano gratuito ou assine', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Streaming limitado a 1 hora por dia. Assine para assistir sem limites, mais telas e canais ao vivo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text(paid.first.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(paid.first.label ?? '', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(height: 14),
            const PaymentBadgesRow(label: 'Assine com'),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () { Navigator.pop(c); context.go('/main/plans'); },
                child: const Text('Ver planos'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Continuar no grátis', style: TextStyle(color: AppColors.textMuted))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
