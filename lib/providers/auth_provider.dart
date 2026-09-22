import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_client.dart';

const _kCachedMeKey = 'pixgo_cached_me';

class AuthState {
  final AppUser? user;
  final AppPlan? plan;
  final List<Profile> profiles;
  final bool hydrated;
  final bool loading;

  const AuthState({
    this.user,
    this.plan,
    this.profiles = const [],
    this.hydrated = false,
    this.loading = false,
  });

  bool get isLoggedIn => user != null;

  AuthState copyWith({
    AppUser? user,
    AppPlan? plan,
    List<Profile>? profiles,
    bool? hydrated,
    bool? loading,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      plan: clearUser ? null : (plan ?? this.plan),
      profiles: clearUser ? const [] : (profiles ?? this.profiles),
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

  AuthState _stateFromMeData(Map<String, dynamic> data, {required bool hydrated}) {
    return AuthState(
      user: data['user'] != null ? AppUser.fromJson(data['user']) : null,
      plan: data['plan'] != null ? AppPlan.fromJson(data['plan']) : AppPlan.free(),
      profiles: ((data['profiles'] as List?) ?? []).map((p) => Profile.fromJson(p)).toList(),
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
      state = _stateFromMeData(data, hydrated: true);
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
      state = _stateFromMeData(data, hydrated: true);
    } catch (e) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  Future<void> logout() async {
    final rt = await _api.refreshToken;
    await authApi.logout(rt);
    await _api.clearTokens();
    await _clearCachedMe();
    state = state.copyWith(clearUser: true, loading: false, hydrated: true);
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
      state = _stateFromMeData(data, hydrated: true);
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
      state = _stateFromMeData(cached, hydrated: true);
    } else {
      state = state.copyWith(hydrated: true);
    }
  }

  Future<void> refreshMe() => fetchMe();
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});
