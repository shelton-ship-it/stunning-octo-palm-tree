import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLangKey = 'pixgo_lang';

/// Estado explícito: evita a ambiguidade de usar Locale? sozinho, onde
/// null tanto podia significar "ainda a carregar do disco" como "utilizador
/// ainda não escolheu idioma" — essa ambiguidade foi a causa do ecrã de
/// idioma aparecer e desaparecer (o router não sabia distinguir os dois casos).
class LocaleState {
  final Locale? locale;
  final bool loaded;
  const LocaleState({this.locale, this.loaded = false});
}

class LocaleController extends StateNotifier<LocaleState> {
  LocaleController() : super(const LocaleState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLangKey);
    state = LocaleState(locale: saved != null ? Locale(saved) : null, loaded: true);
  }

  Future<void> setLocale(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, code);
    // O router reage sozinho a esta mudança de estado (via refreshListenable)
    // e navega para o sítio certo — não é preciso chamar context.go() manualmente.
    state = LocaleState(locale: Locale(code), loaded: true);
  }
}

final localeProvider = StateNotifierProvider<LocaleController, LocaleState>((ref) {
  return LocaleController();
});
