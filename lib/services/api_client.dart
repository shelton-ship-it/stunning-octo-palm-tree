import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// api_client.dart — equivalente Dart de lib/api.ts + a lógica authedFetch de
/// store/auth.ts. Faz refresh automático do token em 401 e repete o pedido
/// uma única vez (mesmo comportamento do frontend original).
///
/// Hosts confirmados em produção (pixel.zip / pixel_service_v1.zip /
/// api-core.rar): api.pixgo.qzz.io (pixel_service — catálogo, conteúdo,
/// stream, canais, progresso, minha lista, pagamentos-leitura) e
/// pixel.pixgo.qzz.io (api-core — login/registo/google alternativo, planos,
/// gateway de pagamento, ZumboPay, device code de TV). O host antigo
/// api.pixgo.frii.site está descontinuado (ver [[streamvault-pixgo]]).
const String kApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.pixgo.qzz.io',
);

/// Host do api-core — só usado para o que NÃO existe no pixel_service:
/// GET /api/payments/gateway e o fluxo ZumboPay (POST charge / GET status).
/// JWT_SECRET/COOKIE_SECRET são partilhados entre os dois backends (mesma
/// tabela `users` no Turso), por isso o mesmo Bearer token do login em
/// api.pixgo.qzz.io é aceite aqui sem novo login.
const String kApiCoreBase = String.fromEnvironment(
  'API_CORE_BASE_URL',
  defaultValue: 'https://pixel.pixgo.qzz.io',
);

/// Domínio do frontend web — usado apenas para a página /embed/watch/:id
/// (ver watch_screen.dart), que reutiliza o componente ShakaPlayer.tsx real
/// dentro de uma WebView, e para o checkout Hotmart (widget JS, só corre no
/// domínio real do hub app.pixgo.qzz.io).
const String kWebBase = String.fromEnvironment(
  'WEB_BASE_URL',
  defaultValue: 'https://pixgo.qzz.io',
);

/// Host do hub de conta/pagamentos (app.rar) — login/registo/checkout.
const String kHubBase = String.fromEnvironment(
  'HUB_BASE_URL',
  defaultValue: 'https://app.pixgo.qzz.io',
);

const _kTokenKey = 'pixgo_token';
const _kRefreshKey = 'pixgo_refresh';

class ApiException implements Exception {
  final int? status;
  final String message;
  final dynamic data;
  ApiException(this.message, {this.status, this.data});
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: '$kApiBase/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));
    _apiCoreDio = Dio(BaseOptions(
      baseUrl: '$kApiCoreBase/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));
    _initCookies();
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;
  late final Dio _apiCoreDio;
  final _storage = const FlutterSecureStorage();
  PersistCookieJar? _cookieJar;
  Future<void>? _cookiesReady;

  /// Cookie jar partilhado entre api.pixgo.qzz.io e pixel.pixgo.qzz.io,
  /// persistido em disco. Necessário para: (1) pv_did — identidade de
  /// dispositivo do pixel_service (middleware/rate-limit.js), host-only,
  /// sem isto o backend vê "dispositivo novo" a cada request; (2)
  /// pixgo_session — Domain=.pixgo.qzz.io, partilhado entre os dois hosts
  /// automaticamente porque é o MESMO cookie jar (RFC 6265: PersistCookieJar
  /// já faz o matching por domínio dos dois Set-Cookie reais).
  void _initCookies() {
    _cookiesReady = () async {
      final dir = await getApplicationSupportDirectory();
      final jar = PersistCookieJar(
        ignoreExpires: false,
        storage: FileStorage('${dir.path}/.cookies/'),
      );
      _cookieJar = jar;
      _dio.interceptors.add(CookieManager(jar));
      _apiCoreDio.interceptors.add(CookieManager(jar));
    }();
  }

  Future<void> get _cookiesLoaded => _cookiesReady ?? Future.value();

  Future<String?> get token async => _storage.read(key: _kTokenKey);
  Future<String?> get refreshToken async => _storage.read(key: _kRefreshKey);

  Future<void> setTokens({required String token, String? refresh}) async {
    await _storage.write(key: _kTokenKey, value: token);
    if (refresh != null) await _storage.write(key: _kRefreshKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _kTokenKey);
    await _storage.delete(key: _kRefreshKey);
    // Logout também deve limpar os cookies (pv_did fica; pixgo_session sai
    // — mesmo efeito de POST /auth/logout no lado do servidor, que invalida
    // a sessão associada a esse cookie).
    await _cookiesLoaded;
    await _cookieJar?.deleteAll();
  }

  Future<String?>? _refreshInFlight;

  Future<String?> _doRefresh() async {
    if (_refreshInFlight != null) return _refreshInFlight;
    _refreshInFlight = _performRefresh();
    try {
      return await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<String?> _performRefresh() async {
    final rt = await refreshToken;
    if (rt == null) return null;
    try {
      final res = await _dio.post('/auth/refresh', data: {'refresh_token': rt});
      final newToken = res.data['token'] as String?;
      final newRefresh = res.data['refresh_token'] as String?;
      if (newToken != null) {
        await setTokens(token: newToken, refresh: newRefresh);
        return newToken;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _req(Dio dio, String method, String path, {dynamic data}) async {
    await _cookiesLoaded;
    final t = await token;
    final opts = Options(method: method, headers: {
      if (t != null) 'Authorization': 'Bearer $t',
    });

    try {
      final res = await dio.request(path, data: data, options: opts);
      return res.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final newToken = await _doRefresh();
        if (newToken == null) {
          throw ApiException('Sessão expirada', status: 401, data: e.response?.data);
        }
        final retryOpts = Options(method: method, headers: {'Authorization': 'Bearer $newToken'});
        try {
          final res2 = await dio.request(path, data: data, options: retryOpts);
          return res2.data;
        } on DioException catch (e2) {
          throw ApiException(
            e2.response?.data?['message'] ?? e2.message ?? 'Request failed',
            status: e2.response?.statusCode,
            data: e2.response?.data,
          );
        }
      }
      throw ApiException(
        e.response?.data?['message'] ?? e.message ?? 'Request failed',
        status: e.response?.statusCode,
        data: e.response?.data,
      );
    }
  }

  // ── api.pixgo.qzz.io (pixel_service) ──────────────────────────────────
  Future<dynamic> get(String path) => _req(_dio, 'GET', path);
  Future<dynamic> post(String path, [dynamic data]) => _req(_dio, 'POST', path, data: data);
  Future<dynamic> put(String path, [dynamic data]) => _req(_dio, 'PUT', path, data: data);
  Future<dynamic> delete(String path) => _req(_dio, 'DELETE', path);

  /// Pedido não autenticado (login/register) — usa o Dio base sem token,
  /// mas COM o cookie jar (o backend define pv_did mesmo em pedidos
  /// anónimos, ver resolveDeviceId em middleware/rate-limit.js).
  Future<dynamic> postPublic(String path, dynamic data) async {
    await _cookiesLoaded;
    try {
      final res = await _dio.post(path, data: data);
      return res.data;
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] ?? e.message ?? 'Request failed',
        status: e.response?.statusCode,
        data: e.response?.data,
      );
    }
  }

  // ── pixel.pixgo.qzz.io (api-core) — só gateway/ZumboPay ───────────────
  Future<dynamic> coreGet(String path) => _req(_apiCoreDio, 'GET', path);
  Future<dynamic> corePost(String path, [dynamic data]) => _req(_apiCoreDio, 'POST', path, data: data);

  /// Copia o cookie pixgo_session (Domain=.pixgo.qzz.io) do jar do Dio para
  /// o CookieManager nativo da WebView — necessário porque a WebView tem o
  /// seu próprio armazenamento de cookies, separado do Dio. Sem isto, abrir
  /// o hub (app.pixgo.qzz.io) numa WebView pediria login de novo mesmo com
  /// sessão válida na app. `uri` deve ser um host que partilha o domínio do
  /// cookie (qualquer *.pixgo.qzz.io).
  Future<void> syncSessionCookieToWebView(Uri uri) async {
    await _cookiesLoaded;
    final jar = _cookieJar;
    if (jar == null) return;
    final cookies = await jar.loadForRequest(Uri.parse('https://api.pixgo.qzz.io'));
    final session = cookies.where((c) => c.name == 'pixgo_session').toList();
    if (session.isEmpty) return;
    final manager = WebViewCookieManager();
    for (final c in session) {
      await manager.setCookie(WebViewCookie(
        name: c.name,
        value: c.value,
        domain: '.pixgo.qzz.io',
        path: '/',
      ));
    }
  }
}

/// ── Endpoints agrupados, espelhando lib/api.ts ──────────────────────────
class AuthApi {
  final _c = ApiClient.instance;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _c.postPublic('/auth/login', {'username': username, 'password': password});
    return data;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final data = await _c.postPublic('/auth/register', body);
    return data;
  }

  Future<Map<String, dynamic>> me() async => await _c.get('/auth/me');
  Future<Map<String, dynamic>> update(Map<String, dynamic> body) async => await _c.put('/auth/me', body);
  Future<void> changePassword(Map<String, dynamic> body) async => await _c.post('/auth/change-password', body);
  Future<void> logout(String? refreshToken) async {
    try {
      await _c.post('/auth/logout', {'refresh_token': refreshToken});
    } catch (_) {}
  }
}

// ── Profiles — matches routes/auth.js (POST/PUT/DELETE /auth/profiles) ───
class ProfilesApi {
  final _c = ApiClient.instance;
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      await _c.post('/auth/profiles', body);
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> body) async =>
      await _c.put('/auth/profiles/$id', body);
  Future<void> delete(String id) async => await _c.delete('/auth/profiles/$id');
}

class CatalogApi {
  final _c = ApiClient.instance;
  Future<Map<String, dynamic>> list([Map<String, dynamic> params = const {}]) async {
    final p = {'lang': 'en', ...params};
    return await _c.get('/catalog?${Uri(queryParameters: _stringify(p)).query}');
  }
  Future<List<dynamic>> featured([int limit = 6]) async {
    final r = await _c.get('/catalog/featured?limit=$limit&lang=en');
    return (r is List) ? r : (r['items'] ?? []);
  }
  Future<List<dynamic>> latest(String type, [int limit = 12]) async {
    final r = await _c.get('/catalog/latest?type=$type&limit=$limit&lang=en');
    return (r is List) ? r : (r['items'] ?? []);
  }
  /// GET /catalog/home — usado pela home real do pixel (featured/popular/
  /// latest por tipo já agrupados num único pedido).
  Future<Map<String, dynamic>> home([String? profileId]) async {
    final qp = profileId != null ? '&profile_id=$profileId' : '';
    return await _c.get('/catalog/home?lang=en$qp');
  }
}

class ContentApi {
  final _c = ApiClient.instance;
  Future<Map<String, dynamic>> get(String id, [String lang = 'en', String? profileId]) async {
    final qp = profileId != null ? '&profile_id=$profileId' : '';
    return await _c.get('/content/$id?lang=$lang$qp');
  }
  Future<Map<String, dynamic>> getStream(String id, [Map<String, dynamic> p = const {}]) async =>
      await _c.get('/content/$id/stream?${Uri(queryParameters: _stringify(p)).query}');
  /// GET /content/:id/download[?episode=] — manifesto de download offline
  /// (license, drm_key_hex, manifest{initUrl,segUrls[],encrypted,segExt},
  /// downloads_remaining/max). 403 quando a cota mensal do plano esgotou
  /// (ApiException.status==403, data['plans'] traz as opções de upgrade).
  Future<Map<String, dynamic>> getDownload(String id, {String? episodeId, String lang = 'en'}) async {
    final qp = episodeId != null ? '&episode=$episodeId' : '';
    return await _c.get('/content/$id/download?lang=$lang$qp');
  }
  /// POST /api/content/:id/heartbeat — chamado a cada 120s enquanto o vídeo
  /// está em reprodução (HEARTBEAT_INTERVAL_MS=120000 no backend,
  /// middleware/rate-limit.js). Devolve o corpo — 409 (sessão substituída)
  /// e 429 (limite diário) chegam como ApiException com esse status.
  Future<Map<String, dynamic>> heartbeat(String id, {int? position, String? episodeId}) async =>
      await _c.post('/content/$id/heartbeat', {
        'position': position ?? 0,
        if (episodeId != null) 'episode': episodeId,
      });
}

class SearchApi {
  final _c = ApiClient.instance;
  Future<Map<String, dynamic>> search(String q, [Map<String, dynamic> p = const {}]) async =>
      await _c.get('/search?${Uri(queryParameters: _stringify({'q': q, 'lang': 'en', ...p})).query}');
  Future<List<dynamic>> popular() async {
    final r = await _c.get('/search/popular?lang=en');
    return (r is List) ? r : [];
  }
}

/// ChannelsApi — a listagem de canais NÃO vem da API (é client-side, via
/// jsDelivr, ver ChannelsSource); esta classe só cobre o que É do backend:
/// o "gate" (verifica acesso/cota antes de tocar) e o heartbeat, exatamente
/// como routes/channels.js + middleware/rate-limit.js (isChannelPlay/
/// isChannelHeartbeat). As rotas /channels, /channels/categories e
/// /channels/search NÃO existem no pixel_service_v1 real — a versão
/// anterior deste ficheiro assumia-as e nunca funcionou.
class ChannelsApi {
  final _c = ApiClient.instance;
  /// GET /api/channels/:id — gate chamado antes de começar a tocar.
  Future<Map<String, dynamic>> get(String id) async => await _c.get('/channels/$id');
  /// POST /api/channels/:id/heartbeat — a cada 120s enquanto o canal toca.
  Future<Map<String, dynamic>> heartbeat(String id, {int? position}) async =>
      await _c.post('/channels/$id/heartbeat', {'position': position ?? 0});
}

/// PaymentsApi — só o que existe de facto: leitura de planos/assinatura em
/// api.pixgo.qzz.io (pixel_service, payments.js) e escolha de gateway +
/// ZumboPay em pixel.pixgo.qzz.io (api-core). A lógica USDT/Polygon
/// (convert/create/status) foi removida do backend (ver [[streamvault-pixgo]]
/// Rodada 3) — a versão anterior deste ficheiro ainda a chamava.
class PaymentsApi {
  final _c = ApiClient.instance;

  Future<List<dynamic>> plans() async {
    final r = await _c.get('/payments/plans');
    return (r is List) ? r : (r['plans'] ?? []);
  }

  Future<Map<String, dynamic>> subscription() async => await _c.get('/payments/subscription');
  Future<List<dynamic>> history() async {
    final r = await _c.get('/payments/history');
    return (r is List) ? r : (r['history'] ?? []);
  }
  Future<void> cancel() async => await _c.post('/payments/cancel');

  /// GET {api-core}/api/payments/gateway?plan=<id> — decidido no servidor
  /// pelo país (geo da EdgeOne). Nunca decidir gateway/moeda no cliente.
  Future<Map<String, dynamic>> gateway(String planId) async =>
      await _c.coreGet('/payments/gateway?plan=$planId');

  /// POST {api-core}/api/payments/zumbopay/charge — só elegível quando
  /// gateway() devolveu 'zumbopay' (país MZ). method: 'mpesa'|'emola'|'card'.
  Future<Map<String, dynamic>> zumbopayCharge({
    required String plan,
    required String method,
    String? msisdn,
  }) async =>
      await _c.corePost('/payments/zumbopay/charge', {
        'plan': plan,
        'method': method,
        if (msisdn != null) 'msisdn': msisdn,
      });

  /// GET {api-core}/api/payments/zumbopay/status/:id — polling a cada 3s,
  /// timeout de 5min (mesmo padrão do ZumboPayCheckout.tsx do hub).
  Future<Map<String, dynamic>> zumbopayStatus(String transactionId) async =>
      await _c.coreGet('/payments/zumbopay/status/$transactionId');
}

class ProgressApi {
  final _c = ApiClient.instance;
  Future<void> update({
    required String profileId,
    required String contentId,
    String? episodeId,
    String lang = 'en',
    required double progress,
    int? duration,
  }) async {
    await _c.post('/progress/update', {
      'profileId': profileId,
      'contentId': contentId,
      'episodeId': episodeId,
      'lang': lang,
      'progress': progress,
      'duration': duration,
    });
  }

  Future<List<dynamic>> continueWatching([Map<String, dynamic> p = const {}]) async {
    final r = await _c.get('/progress/continue?${Uri(queryParameters: _stringify(p)).query}');
    return (r is List) ? r : [];
  }
}

class MyListApi {
  final _c = ApiClient.instance;
  Future<Map<String, dynamic>> list([Map<String, dynamic> p = const {}]) async =>
      await _c.get('/mylist?${Uri(queryParameters: _stringify(p)).query}');
  Future<void> add(String profileId, String contentId) async =>
      await _c.post('/mylist/add', {'profileId': profileId, 'contentId': contentId});
  Future<void> remove(String profileId, String contentId) async =>
      await _c.post('/mylist/remove', {'profileId': profileId, 'contentId': contentId});
  Future<bool> check(String contentId, {String? profileId}) async {
    final qp = profileId != null ? '?profileId=$profileId' : '';
    final r = await _c.get('/mylist/check/$contentId$qp');
    return r['inList'] == true;
  }
}

Map<String, String> _stringify(Map<String, dynamic> m) =>
    m.map((k, v) => MapEntry(k, v?.toString() ?? ''))..removeWhere((k, v) => v.isEmpty);

/// Domínio do Worker de moderação/suporte/chat (copyright-worker.js) —
/// separado da API principal, mesmo padrão do lib/api.ts (uploadReq).
const String kUploadBase = String.fromEnvironment(
  'UPLOAD_BASE_URL',
  defaultValue: 'https://copyright.pixgo.qzz.io',
);

Future<dynamic> _uploadReq(String path, {String method = 'GET', dynamic data}) async {
  final token = await ApiClient.instance.token;
  final dio = Dio(BaseOptions(baseUrl: kUploadBase, headers: {
    if (token != null) 'Authorization': 'Bearer $token',
  }));
  final res = await dio.request(path, data: data, options: Options(method: method));
  return res.data;
}

/// Denúncias, suporte e o chatbot do site (Pixel) — mesmo Worker
/// (copyright.pixgo.qzz.io), endpoints públicos POST /report-abuse,
/// /support e /chat (Bearer opcional).
class ContactApi {
  Future<void> reportAbuse(String contentTitle, String reason) async =>
      await _uploadReq('/report-abuse', method: 'POST', data: {'contentTitle': contentTitle, 'reason': reason});
  Future<void> support(String email, String message) async =>
      await _uploadReq('/support', method: 'POST', data: {'email': email, 'message': message});
}

class ChatApi {
  /// POST /chat {message, history} — history = {role:'user'|'assistant',
  /// content} das últimas 6 mensagens (mesmo formato e limite do
  /// PixelChatbot.tsx real). Resposta: res.reply (confirmado no componente
  /// original — `res.reply || t('chatbot.error')`).
  Future<String?> send(String message, List<Map<String, String>> history) async {
    final res = await _uploadReq('/chat', method: 'POST', data: {'message': message, 'history': history});
    final data = res is Map ? res : <String, dynamic>{};
    return data['reply']?.toString();
  }
}

final authApi = AuthApi();
final profilesApi = ProfilesApi();
final catalogApi = CatalogApi();
final contentApi = ContentApi();
final searchApi = SearchApi();
final channelsApi = ChannelsApi();
final paymentsApi = PaymentsApi();
final progressApi = ProgressApi();
final myListApi = MyListApi();
final contactApi = ContactApi();
final chatApi = ChatApi();
