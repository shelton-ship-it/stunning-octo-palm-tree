import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

/// CheckoutScreen — porte fiel de main/plans/checkout (pixel) +
/// CheckoutPage/ZumboPayCheckout do hub (app.rar). A versão anterior deste
/// ficheiro chamava paymentsApi.convert/create/status — endpoints USDT/
/// Polygon já removidos do backend (ver [[streamvault-pixgo]] Rodada 3).
///
/// GET /api/payments/gateway?plan=<id> decide no SERVIDOR (pelo país)
/// qual gateway usar — nunca decidido no cliente:
///  • hotmart → o widget é JS puro (só corre no domínio real do hub),
///    por isso abre o próprio /main/plans/checkout do hub numa WebView,
///    com o cookie pixgo_session sincronizado primeiro (SSO real).
///  • zumbopay (MZ) → é API pura, replicado 100% nativo (mesmos estados,
///    validação de msisdn, polling 3s/timeout 5min do ZumboPayCheckout.tsx
///    real). Só M-Pesa está habilitado — e-Mola/cartão estão comentados no
///    componente original ("pendente aprovação"/"em breve"), não activados
///    aqui também.
class CheckoutScreen extends ConsumerStatefulWidget {
  final String planId;
  const CheckoutScreen({super.key, required this.planId});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _loading = true;
  String? _error;
  String? _gateway; // 'hotmart' | 'zumbopay'
  double? _amount;
  String? _currency;
  String? _label;

  @override
  void initState() {
    super.initState();
    _resolveGateway();
  }

  Future<void> _resolveGateway() async {
    try {
      final r = await paymentsApi.gateway(widget.planId);
      if (!mounted) return;
      setState(() {
        _gateway = r['gateway']?.toString() ?? 'hotmart';
        _amount = (r['amount'] as num?)?.toDouble();
        _currency = r['currency']?.toString();
        _label = r['label']?.toString();
        _loading = false;
      });
    } catch (_) {
      // Mesma regra do hub: se a escolha de gateway falhar, cai em Hotmart.
      if (!mounted) return;
      setState(() { _gateway = 'hotmart'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.bgDark, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(backgroundColor: AppColors.bgDark),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(backgroundColor: AppColors.bgDark, title: const Text('Checkout')),
      body: _gateway == 'zumbopay'
          ? _ZumboPayCheckout(planId: widget.planId, amount: _amount ?? 0, currency: _currency ?? 'MZN', label: _label)
          : _HotmartCheckout(planId: widget.planId),
    );
  }
}

/// Hotmart — widget JS real, só corre no domínio do hub. WebView aponta
/// directo para app.pixgo.qzz.io/main/plans/checkout (a mesma página que o
/// browser abriria), com o cookie de sessão sincronizado antes de carregar.
class _HotmartCheckout extends ConsumerStatefulWidget {
  final String planId;
  const _HotmartCheckout({required this.planId});
  @override
  ConsumerState<_HotmartCheckout> createState() => _HotmartCheckoutState();
}

class _HotmartCheckoutState extends ConsumerState<_HotmartCheckout> {
  WebViewController? _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ApiClient.instance.syncSessionCookieToWebView(Uri.parse(kHubBase));
    final url = '$kHubBase/main/plans/checkout?plan=${widget.planId}';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          _checkThankYou(req.url);
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) => _checkThankYou(url),
      ))
      ..loadRequest(Uri.parse(url));
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  // Thank-You Pages reais e fixas do hub — /main/plans/checkout/success,
  // /pending, /analysis (ver [[streamvault-pixgo]] Rodada 4).
  void _checkThankYou(String url) {
    if (_done) return;
    if (url.contains('/main/plans/checkout/success') ||
        url.contains('/main/plans/checkout/pending') ||
        url.contains('/main/plans/checkout/analysis')) {
      _done = true;
      ref.read(authProvider.notifier).refreshMe();
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    return WebViewWidget(controller: _controller!);
  }
}

/// ZumboPay — porte 1:1 de ZumboPayCheckout.tsx (estados, validação,
/// polling). method fixo em 'mpesa' (único activado no componente real).
class _ZumboPayCheckout extends ConsumerStatefulWidget {
  final String planId;
  final double amount;
  final String currency;
  final String? label;
  const _ZumboPayCheckout({required this.planId, required this.amount, required this.currency, this.label});
  @override
  ConsumerState<_ZumboPayCheckout> createState() => _ZumboPayCheckoutState();
}

enum _ZpStatus { idle, starting, pending, failed, timeout }

class _ZumboPayCheckoutState extends ConsumerState<_ZumboPayCheckout> {
  static const _pollInterval = Duration(seconds: 3);
  static const _pollTimeout = Duration(minutes: 5);

  final _msisdnController = TextEditingController();
  _ZpStatus _status = _ZpStatus.idle;
  String? _errorMsg;
  Timer? _poll;
  Timer? _timeout;

  @override
  void dispose() {
    _poll?.cancel();
    _timeout?.cancel();
    _msisdnController.dispose();
    super.dispose();
  }

  void _startPolling(String transactionId) {
    _poll = Timer.periodic(_pollInterval, (_) async {
      try {
        final data = await paymentsApi.zumbopayStatus(transactionId);
        if (data['status'] == 'active') {
          _poll?.cancel();
          _timeout?.cancel();
          ref.read(authProvider.notifier).refreshMe();
          if (mounted) context.pop();
        } else if (data['status'] == 'failed') {
          _poll?.cancel();
          _timeout?.cancel();
          if (mounted) setState(() => _status = _ZpStatus.failed);
        }
      } catch (_) {
        // falha de rede pontual — tenta de novo no próximo tick
      }
    });
    _timeout = Timer(_pollTimeout, () {
      _poll?.cancel();
      if (mounted && _status == _ZpStatus.pending) setState(() => _status = _ZpStatus.timeout);
    });
  }

  Future<void> _handleStart() async {
    setState(() { _errorMsg = null; _status = _ZpStatus.starting; });
    try {
      final data = await paymentsApi.zumbopayCharge(
        plan: widget.planId,
        method: 'mpesa',
        msisdn: _msisdnController.text.trim(),
      );
      setState(() => _status = _ZpStatus.pending);
      _startPolling(data['transaction_id'].toString());
    } on ApiException catch (e) {
      setState(() { _status = _ZpStatus.failed; _errorMsg = e.data?['message']?.toString() ?? 'Falha no pagamento.'; });
    } catch (_) {
      setState(() { _status = _ZpStatus.failed; _errorMsg = 'Falha no pagamento.'; });
    }
  }

  bool get _canSubmit =>
      _status != _ZpStatus.starting && _status != _ZpStatus.pending && _msisdnController.text.trim().length >= 9;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Text(widget.label ?? '${widget.amount} ${widget.currency}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.lock, size: 18, color: AppColors.secondary),
            const SizedBox(width: 10),
            const Expanded(child: Text('Pagamento processado com segurança pela ZumboPay', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
          ]),
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: (_status == _ZpStatus.starting || _status == _ZpStatus.pending) ? null : () {},
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('M-Pesa'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _msisdnController,
          keyboardType: TextInputType.phone,
          enabled: _status != _ZpStatus.starting && _status != _ZpStatus.pending,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: '84xxxxxxx ou 86xxxxxxx'),
        ),
        const SizedBox(height: 16),
        if (_status == _ZpStatus.pending)
          _alert('Confirma o PIN no teu telemóvel para concluir o pagamento.', AppColors.secondary),
        if (_status == _ZpStatus.timeout)
          _alert('Ainda não recebemos confirmação — se já pagaste, aguarda mais um pouco; caso contrário, tenta novamente.', Colors.amber),
        if (_status == _ZpStatus.failed)
          _alert(_errorMsg ?? 'Falha no pagamento.', AppColors.primary),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _canSubmit ? _handleStart : null,
            child: Text(_status == _ZpStatus.starting ? context.t('common.loading') : 'Continuar para pagamento'),
          ),
        ),
      ]),
    );
  }

  Widget _alert(String text, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      );
}
