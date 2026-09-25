import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/disclaimer_gate.dart';
import '../../widgets/pixel_chatbot.dart';
import '../../widgets/tv_pairing_dialog.dart';

/// MainShell — bottom nav + Drawer, ligados às MESMAS chaves de tradução
/// que o site usa (assets/i18n/{pt,en,es}.json, chaves nav.*) — trocar de
/// idioma aqui tem o mesmo efeito real que no site.

void _showUploadBlocked(BuildContext context) {
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: Text(c.t('upload.webOnlyTitle')),
      content: Text(
        c.t('upload.webOnlyBody'),
        style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('upload.webOnlyClose'))),
      ],
    ),
  );
}

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    {'path': '/main', 'iconOutline': Icons.home_outlined, 'iconFilled': Icons.home_rounded, 'key': 'nav.home'},
    {'path': '/main/catalog', 'iconOutline': Icons.movie_outlined, 'iconFilled': Icons.movie_rounded, 'key': 'nav.catalog'},
    {'path': '/main/channels', 'iconOutline': Icons.live_tv_outlined, 'iconFilled': Icons.live_tv_rounded, 'key': 'nav.liveTV'},
    {'path': '/main/mylist', 'iconOutline': Icons.bookmark_border_rounded, 'iconFilled': Icons.bookmark_rounded, 'key': 'nav.myList'},
    {'path': '/main/search', 'iconOutline': Icons.search_rounded, 'iconFilled': Icons.search_rounded, 'key': 'nav.search'},
  ];

  int _currentIndex(String location) {
    for (int i = _tabs.length - 1; i >= 0; i--) {
      final path = _tabs[i]['path'] as String;
      if (path == '/main' ? location == '/main' : location.startsWith(path)) return i;
    }
    return 0;
  }

  bool _isActive(String location, String path) =>
      path == '/main' ? location == '/main' : location.startsWith(path);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _currentIndex(location);
    final auth = ref.watch(authProvider);
    final plan = auth.plan;
    final user = auth.user;
    final isPremium = plan != null && plan.id != 'free';
    // canDownload — porte exato do AppShell real (plan.id !== 'free' &&
    // plan.is_active); a versão anterior excluía 'quarterly' por engano
    // (só aceitava monthly/annual).
    final canDownload = plan != null && plan.id != 'free' && plan.isActive;
    final initials = (user?.name.isNotEmpty == true ? user!.name : (user?.username ?? '?'))
        .split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();

    return DisclaimerGate(child: Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: SvgPicture.asset('assets/icons/logo.svg', height: 26),
        actions: [
          _LanguageMenuButton(),
          if (canDownload)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: context.t('nav.downloads'),
              onPressed: () => context.push('/main/downloads'),
            ),
          IconButton(
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary,
              child: Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            tooltip: auth.activeProfile?.name ?? user?.name ?? '',
            onPressed: () => _showUserMenu(context, ref),
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: _AppDrawer(
        location: location,
        isActive: _isActive,
        isPremium: isPremium,
        canDownload: canDownload,
        userName: user?.name,
        username: user?.username,
        userEmail: user?.email,
        planId: plan?.id ?? 'free',
        initials: initials,
      ),
      body: SafeArea(
        top: false,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 76),
            child: child,
          ),
          const PixelChatbot(),
        ]),
      ),
      bottomNavigationBar: _PixgoBottomNav(tabs: _tabs, currentIndex: idx),
    ));
  }

  /// Menu do utilizador — porte do dropdown de avatar do AppShell real:
  /// dados da conta, lista de perfis (trocar de perfil — não existia
  /// nenhuma forma disto na app), depois conta/upgrade/minha lista/
  /// downloads, upload, e sair.
  void _showUserMenu(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    final user = auth.user;
    final plan = auth.plan;
    final isPremium = plan != null && plan.id != 'free';
    final canDownload = plan != null && plan.id != 'free' && plan.isActive;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('@${user?.username ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              if (user?.email != null) Text(user!.email!, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPremium ? AppColors.primary.withOpacity(0.15) : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  (plan?.id ?? 'free')[0].toUpperCase() + (plan?.id ?? 'free').substring(1),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: isPremium ? AppColors.primary : AppColors.textMuted),
                ),
              ),
            ]),
          ),
          if (auth.profiles.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.t('nav.profiles'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
              ),
            ),
            ...auth.profiles.map((p) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.primary,
                    child: Text((p.name?.isNotEmpty == true ? p.name![0] : '?').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  title: Text(p.name ?? '', style: const TextStyle(fontSize: 13.5)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (p.isKid) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.child_care, size: 15, color: AppColors.textMuted)),
                    if (p.id == auth.activeProfileId) const Icon(Icons.check, size: 16, color: AppColors.primary),
                  ]),
                  onTap: () {
                    ref.read(authProvider.notifier).setActiveProfile(p.id);
                    Navigator.pop(sheetCtx);
                  },
                )),
          ],
          const Divider(height: 1, color: AppColors.border),
          ListTile(dense: true, title: Text(context.t('nav.account')), onTap: () { Navigator.pop(sheetCtx); context.push('/main/account'); }),
          ListTile(dense: true, title: Text(context.t('nav.upgrade')), onTap: () { Navigator.pop(sheetCtx); context.go('/main/plans'); }),
          ListTile(dense: true, title: Text(context.t('nav.myList')), onTap: () { Navigator.pop(sheetCtx); context.go('/main/mylist'); }),
          if (canDownload)
            ListTile(dense: true, title: const Text('Downloads'), onTap: () { Navigator.pop(sheetCtx); context.push('/main/downloads'); }),
          ListTile(
            dense: true,
            leading: const Icon(Icons.connected_tv_rounded, size: 18, color: AppColors.textMuted),
            title: const Text('Parear com a TV'),
            onTap: () {
              Navigator.pop(sheetCtx);
              showDialog(context: context, builder: (_) => const TvPairingDialog());
            },
          ),
          const Divider(height: 1, color: AppColors.border),
          ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_upload_rounded, size: 18, color: AppColors.textMuted),
            title: Text(context.t('nav.upload')),
            onTap: () { Navigator.pop(sheetCtx); _showUploadBlocked(context); },
          ),
          const Divider(height: 1, color: AppColors.border),
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout_rounded, size: 18, color: AppColors.primary),
            title: Text(context.t('nav.signOut'), style: const TextStyle(color: AppColors.primary)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/auth/login');
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

/// Footer de navegação próprio — substitui o BottomNavigationBar padrão do
/// Material (sem personalização nenhuma, "chrome" genérico do Android) por
/// algo mais alinhado com apps de vídeo de referência (YouTube): ícones
/// que mudam de contorno para preenchido consoante o estado selecionado,
/// borda subtil separando do conteúdo, sem splash/ripple visível, só cor +
/// forma do ícone a indicar seleção.
/// _PixgoBottomNav — pendência #8: visual mais próximo do padrão
/// Netflix/YouTube (aba activa com "pill" atrás do ícone + transição
/// suave), mantendo a MESMA lógica de navegação (context.go), os mesmos
/// ícones/labels/traduções e a mesma paleta — é só uma melhoria visual,
/// sem tocar em nenhuma função. splash/highlight passam a usar uma tinta
/// muito subtil (em vez de totalmente transparente) só para dar feedback
/// real ao toque — isto não é "hover" (mobile não tem hover), é feedback
/// de toque, que faltava.
class _PixgoBottomNav extends StatelessWidget {
  final List<Map<String, dynamic>> tabs;
  final int currentIndex;
  const _PixgoBottomNav({required this.tabs, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDarker,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final t = tabs[i];
              final selected = i == currentIndex;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    splashColor: AppColors.primary.withOpacity(0.08),
                    highlightColor: AppColors.primary.withOpacity(0.05),
                    onTap: () => context.go(t['path'] as String),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary.withOpacity(0.14) : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              selected ? t['iconFilled'] as IconData : t['iconOutline'] as IconData,
                              size: 22,
                              color: selected ? AppColors.primary : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? AppColors.primary : AppColors.textMuted,
                            ),
                            child: Text(
                              context.t(t['key'] as String),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Botão de idioma na AppBar — equivalente ao seletor PT/EN/ES do header original.
class _LanguageMenuButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider).locale?.languageCode ?? 'pt';
    return PopupMenuButton<String>(
      icon: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.translate, size: 18),
        const SizedBox(width: 3),
        Text(current.toUpperCase(), style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      ]),
      onSelected: (code) => ref.read(localeProvider.notifier).setLocale(code),
      itemBuilder: (c) => const [
        PopupMenuItem(value: 'pt', child: Text('🇧🇷  Português')),
        PopupMenuItem(value: 'en', child: Text('🇺🇸  English')),
        PopupMenuItem(value: 'es', child: Text('🇪🇸  Español')),
      ],
    );
  }
}

/// Drawer — equivalente completo à sidebar do AppShell.tsx original.
class _AppDrawer extends ConsumerWidget {
  final String location;
  final bool Function(String, String) isActive;
  final bool isPremium;
  final bool canDownload;
  final String? userName;
  final String? username;
  final String? userEmail;
  final String planId;
  final String initials;

  const _AppDrawer({
    required this.location,
    required this.isActive,
    required this.isPremium,
    required this.canDownload,
    required this.userName,
    required this.username,
    required this.userEmail,
    required this.planId,
    required this.initials,
  });

  static const _menu = [
    {'path': '/main', 'icon': Icons.home_rounded, 'key': 'nav.home'},
    {'path': '/main/catalog', 'icon': Icons.movie_rounded, 'key': 'nav.catalog'},
    {'path': '/main/channels', 'icon': Icons.live_tv_rounded, 'key': 'nav.liveTV'},
    {'path': '/main/mylist', 'icon': Icons.bookmark_rounded, 'key': 'nav.myList'},
    {'path': '/main/search', 'icon': Icons.search_rounded, 'key': 'nav.search'},
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: AppColors.bgDarker,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset('assets/icons/logo.svg', height: 30),
                  const SizedBox(height: 16),
                  Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary,
                      child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(userName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('@${username ?? ''}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isPremium ? AppColors.primary.withOpacity(0.15) : Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(planId, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _sectionLabel(context, 'Menu'),
                  ..._menu.map((item) => _navTile(
                        context,
                        icon: item['icon'] as IconData,
                        label: context.t(item['key'] as String),
                        active: isActive(location, item['path'] as String),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(item['path'] as String);
                        },
                      )),
                  const SizedBox(height: 10),
                  _sectionLabel(context, context.t('account.title')),
                  _navTile(
                    context,
                    icon: Icons.download_rounded,
                    label: context.t('nav.downloads'),
                    active: isActive(location, '/main/downloads'),
                    trailing: !canDownload
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                            child: const Text('PRO', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (canDownload) {
                        context.push('/main/downloads');
                      } else {
                        context.go('/main/plans');
                      }
                    },
                  ),
                  _navTile(
                    context,
                    icon: Icons.cloud_upload_rounded,
                    label: context.t('nav.upload'),
                    active: false,
                    onTap: () {
                      Navigator.pop(context);
                      _showUploadBlocked(context);
                    },
                  ),
                  _navTile(
                    context,
                    icon: Icons.bolt_rounded,
                    label: context.t('nav.upgrade'),
                    active: isActive(location, '/main/plans'),
                    trailing: !isPremium
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                            child: const Text('Free', style: TextStyle(fontSize: 9, color: Colors.white)),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/main/plans');
                    },
                  ),
                  _navTile(
                    context,
                    icon: Icons.settings_rounded,
                    label: context.t('nav.account'),
                    active: isActive(location, '/main/account'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/main/account');
                    },
                  ),
                  _navTile(
                    context,
                    icon: Icons.gavel_rounded,
                    label: context.t('legal.title'),
                    active: isActive(location, '/main/legal'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/main/legal');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse('mailto:${context.t('contact.copyrightEmail')}'));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    border: Border.all(color: AppColors.primary.withOpacity(0.15)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(children: [
                    const Icon(Icons.email_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('contact.copyright'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                      Text(context.t('contact.copyrightEmail'), style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, size: 19, color: AppColors.textMuted),
                title: Text(context.t('nav.signOut'), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                dense: true,
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/auth/login');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textMuted)),
      );

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 19, color: active ? AppColors.primary : AppColors.textMuted),
      title: Text(label, style: TextStyle(fontSize: 13, color: active ? AppColors.textTitle : AppColors.textMuted, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
      trailing: trailing,
      selected: active,
      selectedTileColor: AppColors.primary.withOpacity(0.06),
      onTap: onTap,
    );
  }
}
