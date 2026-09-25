import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_client.dart';

const _kCachedMeKey = 'pixgo_cached_me';
const _kActiveProfileKey = 'pixgo_active_profile';

class AuthState {
  final AppUser? user;
  final AppPlan? plan;
  final List<Profile> profiles;
  final String? activeProfileId;
  final bool hydrated;
  final bool loading;

  const AuthState({
    this.user,
    this.plan,
    this.profiles = const [],
    this.activeProfileId,
    this.hydrated = false,
    this.loading = false,
  });

  bool get isLoggedIn => user != null;

  /// O perfil activo — porte de resolveActiveProfileId(profiles) do site
  /// real: usa o guardado se ainda existir na lista, senão o primeiro.
  Profile? get activeProfile {
    if (profiles.isEmpty) return null;
    return profiles.firstWhere(
      (p) => p.id == activeProfileId,
      orElse: () => profiles.first,
    );
  }

  AuthState copyWith({
    AppUser? user,
    AppPlan? plan,
    List<Profile>? profiles,
    String? activeProfileId,
    bool? hydrated,
    bool? loading,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      plan: clearUser ? null : (plan ?? this.plan),
      profiles: clearUser ? const [] : (profiles ?? this.profiles),
      activeProfileId: clearUser ? null : (activeProfileId ?? this.activeProfileId),
      hydrated: hydrated ?? this.hydrated,
      loading: loading ?? this.loading,
    );
  }
}

/// AuthController — equivalente a store/auth.ts (Zustand).
///
/// Fix crítico de UX: antes, qualquer erro em fetchMe() (incluindo
/// simplesmente não haver rede) limpava os tokens e terminava a sessão —
/// forçando login de novo sempre que o telemóvel ficasse offline, mesmo com
/// um token válido por 365 dias. Agora:
///   - Só um 401 real (confirmado pelo servidor) termina a sessão.
///   - Qualquer outro erro (sem rede, timeout, servidor em baixo) mantém a
///     sessão usando os últimos dados de utilizador guardados em cache local.
class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState()) {
    fetchMe();
  }

  final _api = ApiClient.instance;

  Future<void> _cacheMe(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedMeKey, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> _loadCachedMe() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCachedMeKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearCachedMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedMeKey);
  }

  /// Porte exato de resolveActiveProfileId() do store/auth.ts real.
  Future<String?> _resolveActiveProfileId(List<Profile> profiles) async {
    if (profiles.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kActiveProfileKey);
    if (stored != null && profiles.any((p) => p.id == stored)) return stored;
    return profiles.first.id;
  }

  /// setActiveProfile — troca de perfil (issue: não havia forma nenhuma de
  /// abrir outro perfil na app; o site guarda isto em localStorage e o
  /// resto da app já lê `activeProfile`/`activeProfileId`).
  Future<void> setActiveProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveProfileKey, id);
    state = state.copyWith(activeProfileId: id);
  }

  Future<AuthState> _stateFromMeData(Map<String, dynamic> data, {required bool hydrated}) async {
    final profiles = ((data['profiles'] as List?) ?? []).map((p) => Profile.fromJson(p)).toList();
    final activeId = await _resolveActiveProfileId(profiles);
    return AuthState(
      user: data['user'] != null ? AppUser.fromJson(data['user']) : null,
      plan: data['plan'] != null ? AppPlan.fromJson(data['plan']) : AppPlan.free(),
      profiles: profiles,
      activeProfileId: activeId,
      hydrated: hydrated,
      loading: false,
    );
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(loading: true);
    try {
      final data = await authApi.login(username, password);
      await _api.setTokens(token: data['token'], refresh: data['refresh_token']);
      await _cacheMe(data);
      state = await _stateFromMeData(data, hydrated: true);
    } catch (e) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  /// Login Google (pendência #11) — o JWT já vem pronto do cookie
  /// `pixgo_session` que o hub deixou gravado depois do login real na
  /// WebView (ver hub_login_webview_screen.dart + readHubSessionCookie em
  /// api_client.dart). Não há resposta JSON própria desta vez (o hub é
  /// quem fala com a API, não esta app) — por isso guarda o token
  /// directamente e usa fetchMe() para preencher o resto do estado
  /// (perfis/plano/etc.), exactamente como já acontece ao restaurar sessão
  /// no arranque da app.
  Future<void> loginWithHubSession(String jwt) async {
    state = state.copyWith(loading: true);
    try {
      await _api.setTokens(token: jwt, refresh: '');
      await fetchMe();
    } catch (e) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  Future<void> register(Map<String, dynamic> body) async {
    state = state.copyWith(loading: true);
    try {
      final data = await authApi.register(body);
      await _api.setTokens(token: data['token'], refresh: data['refresh_token']);
      await _cacheMe(data);
      state = await _stateFromMeData(data, hydrated: true);
    } catch (e) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  /// Logout — porte da optimização real: limpa tudo localmente e reage na
  /// hora (mesmo frame), dispara o pedido ao servidor em paralelo sem
  /// esperar por ele (antes o botão ficava 3-5s "preso" à espera do
  /// endpoint acordar — exatamente o padrão de "botões com atraso" achado
  /// no frontend_web real e replicado aqui).
  Future<void> logout() async {
    final rt = await _api.refreshToken;
    await _api.clearTokens();
    await _clearCachedMe();
    state = state.copyWith(clearUser: true, loading: false, hydrated: true);
    authApi.logout(rt); // melhor esforço, sem await
  }

  Future<void> fetchMe() async {
    final hasToken = await _api.token != null;
    final hasRefresh = await _api.refreshToken != null;
    if (!hasToken && !hasRefresh) {
      state = state.copyWith(hydrated: true);
      return;
    }

    try {
      final data = await authApi.me();
      await _cacheMe(data);
      state = await _stateFromMeData(data, hydrated: true);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _api.clearTokens();
        await _clearCachedMe();
        state = state.copyWith(clearUser: true, hydrated: true);
      } else {
        await _restoreFromCacheOrKeepSession();
      }
    } catch (_) {
      await _restoreFromCacheOrKeepSession();
    }
  }

  Future<void> _restoreFromCacheOrKeepSession() async {
    final cached = await _loadCachedMe();
    if (cached != null) {
      state = await _stateFromMeData(cached, hydrated: true);
    } else {
      state = state.copyWith(hydrated: true);
    }
  }

  Future<void> refreshMe() => fetchMe();
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});
