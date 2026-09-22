import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sistema de traduções leve e sem dependências externas.
/// Carrega assets/i18n/{pt,en,es}.json (os MESMOS ficheiros do site) e
/// resolve chaves com dot-notation, ex: t('auth.signIn').
class AppLocalizations {
  AppLocalizations(this.locale, this._strings);

  final Locale locale;
  final Map<String, dynamic> _strings;

  static AppLocalizations of(BuildContext context) {
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l == null) {
      throw FlutterError('AppLocalizations não encontrado no contexto.');
    }
    return l;
  }

  static const supportedLocales = [Locale('pt'), Locale('en'), Locale('es')];

  String t(String key, {Map<String, String>? args}) {
    final parts = key.split('.');
    dynamic cur = _strings;
    for (final p in parts) {
      if (cur is Map<String, dynamic> && cur.containsKey(p)) {
        cur = cur[p];
      } else {
        return key; // fallback: devolve a própria chave (visível em dev)
      }
    }
    String result = cur?.toString() ?? key;
    if (args != null) {
      args.forEach((k, v) {
        result = result.replaceAll('{{$k}}', v);
      });
    }
    return result;
  }

  static const delegate = _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['pt', 'en', 'es'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final code = ['pt', 'en', 'es'].contains(locale.languageCode) ? locale.languageCode : 'pt';
    final raw = await rootBundle.loadString('assets/i18n/$code.json');
    final Map<String, dynamic> json = jsonDecode(raw);
    return AppLocalizations(locale, json);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Atalho de conveniência: `context.t('auth.signIn')`
extension LocalizationsExt on BuildContext {
  String t(String key, {Map<String, String>? args}) =>
      AppLocalizations.of(this).t(key, args: args);
}
