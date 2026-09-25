import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

/// HubLoginWebViewScreen — pendência #11 (Login Google), versão corrigida.
///
/// A 1ª tentativa integrava o SDK nativo do Google a falar directamente
/// com o pixel_service_v1 — mas isso "inventava" um caminho novo. Ao ler
/// api-core.rar + app.rar (o backend/frontend do HUB) ficou claro que:
///   • pixgo.qzz.io (frontend_web) NUNCA teve UI de login própria — só
///     redirecciona para app.pixgo.qzz.io/auth/login (ver
///     frontend_web/src/app/auth/login/page.tsx, ~2026).
///   • O botão "Continuar com Google" REAL, já em produção, vive só no hub
///     (app.rar/LoginPage.tsx + components/ui/GoogleAuthButton.tsx),
///     falando com api-core (POST /api/auth/google lá, não no
///     pixel_service_v1 — aquele endpoint existe mas é uma cópia paralela
///     não usada por ninguém em produção).
///
/// Solução sem inventar nada novo: abrir a PRÓPRIA página do hub numa
/// WebView — o MESMO padrão já validado no checkout Hotmart
/// (checkout_screen.dart) — deixando o hub tratar de tudo (tradicional OU
/// Google, é a mesma página, o mesmo botão). Quando o login termina, o hub
/// já deixou gravado o cookie partilhado `pixgo_session` (httpOnly,
/// domínio `.pixgo.qzz.io`) — este ecrã lê-o nativamente (ver
/// MainActivity.kt + ApiClient.readHubSessionCookie) e usa-o directamente
/// como token da app: é literalmente o MESMO JWT que o login tradicional
/// devolveria no corpo da resposta (routes/auth.js,
/// `setSharedSessionCookie(res, token)` usa a mesma variável `token`).
class HubLoginWebViewScreen extends ConsumerStatefulWidget {
  const HubLoginWebViewScreen({super.key});

  @override
  ConsumerState<HubLoginWebViewScreen> createState() => _HubLoginWebViewScreenState();
}

class _HubLoginWebViewScreenState extends ConsumerState<HubLoginWebViewScreen> {
  static final Uri _returnTo = Uri.parse('$kHubBase/main');

  WebViewController? _controller;
  bool _pageLoading = true;
  bool _finishing = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final loginUrl = '$kHubBase/auth/login?return_to=${Uri.encodeComponent(_returnTo.toString())}';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // Só verifica em onPageFinished (não em onNavigationRequest): o
        // cookie Set-Cookie da resposta de redirect só fica garantidamente
        // gravado no CookieManager nativo depois da página carregar — ler
        // cedo demais arriscava um falso negativo mesmo com o login já
        // concluído.
        onPageFinished: (url) {
          if (mounted) setState(() => _pageLoading = false);
          _checkDone(url);
        },
      ))
      ..loadRequest(Uri.parse(loginUrl));
    _controller = controller;
  }

  /// O hub só sai de /auth/... depois de autenticar com sucesso (login()
  /// e loginWithGoogle() em LoginPage.tsx chamam ambos goAfterAuth(), que
  /// navega para return_to) — qualquer URL do hub fora de /auth/ conta
  /// como login concluído, seja qual for o método usado lá dentro.
  void _checkDone(String url) {
    if (_done) return;
    final u = Uri.tryParse(url);
    if (u == null) return;
    if (u.host == _returnTo.host && !u.path.startsWith('/auth')) {
      _done = true;
      _finish();
    }
  }

  Future<void> _finish() async {
    setState(() { _finishing = true; _error = null; });
    final jwt = await ApiClient.instance.readHubSessionCookie();
    if (jwt == null) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _done = false; // permite tentar de novo se o utilizador repetir o login
        _error = 'Não foi possível confirmar a sessão. Tente novamente.';
      });
      return;
    }
    try {
      await ref.read(authProvider.notifier).loginWithHubSession(jwt);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _done = false;
        _error = 'Falha ao entrar. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text('Entrar', style: TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(children: [
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_pageLoading || _finishing)
          Container(
            color: AppColors.bgDark.withOpacity(0.85),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
        if (_error != null)
          Positioned(
            left: 16, right: 16, bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            ),
          ),
      ]),
    );
  }
}
