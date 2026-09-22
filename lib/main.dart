import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgDarker,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: PixgoApp()));
}

class PixgoApp extends ConsumerWidget {
  const PixgoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final localeState = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Pixgo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      locale: localeState.locale,
      supportedLocales: const [Locale('pt'), Locale('en'), Locale('es')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // Sem estes 3, qualquer TextField que precise de localizações do
        // Material (ex: menu de seleção de texto) lança "No
        // MaterialLocalizations found" e o Flutter desenha o widget de erro
        // no lugar — que em modo release aparece como um bloco cinzento
        // sólido a ocupar todo o espaço disponível. Era exatamente este o
        // bug reportado (idêntico ao github.com/flutter/flutter/issues/132462).
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
