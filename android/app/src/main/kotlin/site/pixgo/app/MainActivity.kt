package site.pixgo.app

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal nativo mínimo — pendência #11 (Login Google), 2ª tentativa.
 *
 * A 1ª tentativa integrava o SDK nativo do Google (google_sign_in) a falar
 * directamente com o pixel_service_v1 — mas o login/registo (incluindo o
 * botão "Continuar com Google" REAL, já em produção) nunca viveu ali nem
 * no frontend_web: vive centralizado no hub (app.pixgo.qzz.io, ver
 * app.rar/LoginPage.tsx + GoogleAuthButton.tsx), que fala com api-core.
 * pixgo.qzz.io (o site) nem tem UI de login própria — só redirecciona pra
 * lá (ver frontend_web/src/app/auth/login/page.tsx).
 *
 * A forma correcta de reaproveitar isto — sem inventar nada novo no
 * backend nem duplicar o botão do Google — é abrir a PRÓPRIA página do hub
 * numa WebView (o mesmo padrão já usado e validado no checkout Hotmart,
 * ver checkout_screen.dart) e, quando o login terminar (tradicional OU
 * Google, é a mesma página), ler o cookie `pixgo_session` que o hub já
 * deixou gravado. Esse cookie é `httpOnly` (por segurance, de propósito) —
 * dá para escrevê-lo via WebViewCookieManager (é o que
 * syncSessionCookieToWebView já faz, no sentido contrário), mas NÃO dá
 * para o ler em Dart nem via JavaScript (document.cookie nunca vê cookies
 * httpOnly). Só o Android nativo consegue — daí este canal, que só faz
 * uma leitura (`CookieManager.getInstance().getCookie`), nada mais.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "site.pixgo.app/webview_cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookie" -> {
                    val url = call.argument<String>("url")
                    val name = call.argument<String>("name")
                    if (url == null || name == null) {
                        result.error("bad_args", "url e name são obrigatórios", null)
                        return@setMethodCallHandler
                    }
                    val raw = CookieManager.getInstance().getCookie(url)
                    val value = raw
                        ?.split("; ")
                        ?.map { it.split("=", limit = 2) }
                        ?.firstOrNull { it.size == 2 && it[0] == name }
                        ?.getOrNull(1)
                    result.success(value)
                }
                else -> result.notImplemented()
            }
        }
    }
}
