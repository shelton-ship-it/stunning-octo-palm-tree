import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

/// PlansScreen — porte 1:1 de main/plans/page.tsx real: planos vêm de
/// GET /api/payments/plans (name/label/features[]/max_profiles/
/// max_downloads), nada de preço/telas/4K inventado no cliente — esses
/// eram os valores fabricados que existiam na versão anterior (baseada no
/// pagamento USDT/Polygon já removido do backend, ver [[streamvault-pixgo]]
/// Rodada 3). Texto dos botões ("Assinar"/"Plano atual") é literal no
/// próprio código-fonte real, não vem de i18n.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});
  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _loading = true;
  bool _error = false;
  List<AppPlan> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final raw = await paymentsApi.plans();
      setState(() {
        _plans = raw
            .map((e) => AppPlan.fromJson(e as Map<String, dynamic>))
            .where((p) => p.id != 'free')
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final plan = auth.plan;
    final isPremium = plan != null && plan.id != 'free';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('plans.title'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(context.t('plans.subtitle'), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary)))
          else if (_error)
            const Text('Não foi possível carregar os planos agora. Tenta novamente em instantes.', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
          else
            ..._plans.map((p) {
              final isCurrent = isPremium && plan.id == p.id;
              final isFeatured = p.id == 'annual'; // "Melhor valor" — mesma convenção da página real
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isFeatured ? AppColors.primary.withOpacity(0.4) : AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (isFeatured)
                      Align(alignment: Alignment.centerRight, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                        child: const Text('Melhor valor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                      )),
                    Text(p.name, style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(p.label ?? '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    ...p.features.map((f) => _bullet(f)),
                    _bullet('${p.maxProfiles ?? 1} ${(p.maxProfiles ?? 1) == 1 ? 'perfil' : 'perfis'}'),
                    _bullet(p.maxDownloads == null ? 'Downloads ilimitados' : 'Até ${p.maxDownloads} downloads/mês'),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: isCurrent
                          ? OutlinedButton(onPressed: null, child: const Text('Plano atual'))
                          : ElevatedButton(
                              onPressed: () => context.push('/main/plans/checkout?plan=${p.id}'),
                              child: const Text('Assinar'),
                            ),
                    ),
                  ]),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check, size: 14, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
        ]),
      );
}
