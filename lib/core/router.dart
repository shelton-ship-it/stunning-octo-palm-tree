import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/main/main_shell.dart';
import '../screens/main/home_screen.dart';
import '../screens/main/catalog_screen.dart';
import '../screens/main/channels_screen.dart';
import '../screens/main/mylist_screen.dart';
import '../screens/main/search_screen.dart';
import '../screens/main/account_screen.dart';
import '../screens/main/legal_screen.dart';
import '../screens/main/downloads_screen.dart';
import '../screens/main/plans_screen.dart';
import '../screens/main/checkout_screen.dart';
import '../screens/main/content_detail_screen.dart';
import '../screens/main/watch_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/language_screen.dart';

/// Dados do canal já conhecidos no momento do toque (vindos do
/// client-side ChannelsSource) — passados por `extra` para WatchScreen
/// porque o gate real (GET /api/channels/:id) não devolve dados do canal.
class ChannelNavData {
  final String name;
  final String? logo;
  final String? url;
  const ChannelNavData({required this.name, this.logo, this.url});
}

/// Router — ÚNICA fonte de verdade para navegação.
///
/// Antes, o SplashScreen também navegava por si próprio (context.go), ao
/// mesmo tempo que este redirect fazia o mesmo com base no auth. Os dois
/// mecanismos competiam entre si, e como o auth "hidrata" quase
/// instantaneamente quando não há sessão guardada, o redirect do router
/// disparava ANTES do ecrã de idioma sequer aparecer direito — daí o
/// "aparece e desaparece". Agora só este redirect decide, com base no
/// estado combinado de locale + auth, e nenhum widget chama context.go()
/// para navegação "de arranque".
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AppListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final localeState = ref.read(localeProvider);
      final loc = state.matchedLocation;

      // 1) Enquanto idioma OU auth ainda não terminaram de carregar do
      //    disco, fica no splash (nunca decide nada a meio de um carregamento).
      if (!localeState.loaded || !auth.hydrated) {
        return loc == '/' ? null : '/';
      }

      // 2) Idioma ainda não escolhido → força o ecrã de idioma (rota
      //    própria, não um widget condicional dentro do splash).
      if (localeState.locale == null) {
        return loc == '/language' ? null : '/language';
      }

      // 3) A partir daqui, idioma já está definido — decide por autenticação.
      final loggingIn = loc.startsWith('/auth');
      final onLanguageOrSplash = loc == '/language' || loc == '/';

      if (!auth.isLoggedIn) {
        return loggingIn ? null : '/auth/login';
      }
      // Autenticado: nunca deve ficar preso no splash, no ecrã de idioma
      // ou nas páginas de login/registo.
      if (loggingIn || onLanguageOrSplash) return '/main';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/language', builder: (c, s) => const LanguageScreen()),
      GoRoute(path: '/auth/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/auth/register', builder: (c, s) => const RegisterScreen()),

      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/main', builder: (c, s) => const HomeScreen()),
          GoRoute(path: '/main/catalog', builder: (c, s) => const CatalogScreen()),
          GoRoute(path: '/main/channels', builder: (c, s) => const ChannelsScreen()),
          GoRoute(path: '/main/mylist', builder: (c, s) => const MyListScreen()),
          GoRoute(path: '/main/search', builder: (c, s) => const SearchScreen()),
          GoRoute(path: '/main/account', builder: (c, s) => const AccountScreen()),
          GoRoute(path: '/main/legal', builder: (c, s) => const LegalScreen()),
          GoRoute(path: '/main/downloads', builder: (c, s) => const DownloadsScreen()),
          GoRoute(path: '/main/plans', builder: (c, s) => const PlansScreen()),
          GoRoute(
            path: '/main/plans/checkout',
            builder: (c, s) => CheckoutScreen(planId: s.uri.queryParameters['plan'] ?? 'monthly'),
          ),
          GoRoute(
            path: '/main/content/:id',
            builder: (c, s) => ContentDetailScreen(id: s.pathParameters['id']!),
          ),
        ],
      ),

      // Watch fica fora da shell (fullscreen, sem bottom nav)
      GoRoute(
        path: '/main/watch/:id',
        builder: (c, s) {
          // Canais: channels_screen.dart passa os dados já conhecidos do
          // client-side (id/name/logo/url) via `extra`, porque o gate real
          // GET /api/channels/:id devolve só {ok:true} — não repete dados
          // do canal (ver routes/channels.js). VOD não usa `extra`.
          final extra = s.extra;
          ChannelNavData? channelData;
          if (extra is ChannelNavData) channelData = extra;
          return WatchScreen(
            id: s.pathParameters['id']!,
            offline: s.uri.queryParameters['offline'] == '1',
            episodeId: s.uri.queryParameters['ep'],
            channelData: channelData,
          );
        },
      ),
    ],
  );
});

/// Notifica o GoRouter sempre que auth OU locale mudam de estado, para
/// o redirect acima ser reavaliado — é o ÚNICO gatilho de navegação
/// automática em toda a app.
class _AppListenable extends ChangeNotifier {
  _AppListenable(this.ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
    ref.listen(localeProvider, (_, __) => notifyListeners());
  }
  final Ref ref;
}
