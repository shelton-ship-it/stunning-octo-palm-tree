import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/channels_source.dart';
import '../../widgets/plan_modals.dart';
import '../../widgets/skeletons.dart';

/// ChannelsScreen — porte fiel de main/channels/page.tsx (pixel.zip).
/// A listagem é 100% client-side (ChannelsSource → jsDelivr), igual ao
/// site; o backend só entra no gate/heartbeat quando um canal é aberto
/// (ver watch_screen.dart). Réplica também do "gap" conhecido e real do
/// site: quando a URL já vem embutida na listagem (utilizador com sessão),
/// o toque abre direto o player sem chamar o gate — só o heartbeat
/// subsequente aplica a cota; sem mudar esse comportamento (fora do
/// pedido), só reproduzido fielmente.
const _limit = 24;

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});
  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  List<ChannelListItem> _channels = [];
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  bool _searching = false;
  String _search = '';
  String? _selectedCategory;
  List<({String name, String slug, int count})> _categories = [];

  // Filtro padrão "Anime" (pendência #3) — réplica fiel de
  // main/channels/page.tsx: a categoria real chamada "Animation" fica
  // seleccionada por omissão (comparação normalizada, sem acentos/caixa,
  // igual ao normalizeStr do site) até o utilizador procurar, escolher
  // outra categoria à mão, ou desligar no botão "Anime"/"Todos".
  bool _animeOnly = true;

  bool _disposed = false;
  final _searchController = TextEditingController();

  bool get _hasUser => ref.read(authProvider).isLoggedIn;

  String _normalizeStr(String s) => s.trim().toLowerCase();

  /// Slug real da categoria "Animation" (nome real dos dados do iptv-org —
  /// "Anime" é só o rótulo mostrado ao utilizador, igual ao site).
  String? get _animeCategorySlug {
    for (final c in _categories) {
      if (_normalizeStr(c.name) == 'animation') return c.slug;
    }
    return null;
  }

  /// Categoria efectivamente aplicada ao pedido — a escolhida à mão tem
  /// sempre prioridade; o default "Anime" só entra quando não há busca
  /// nem categoria manual seleccionada (igual ao `effectiveCategory` do
  /// site).
  String? get _effectiveCategory =>
      (_animeOnly && _search.isEmpty && _selectedCategory == null) ? _animeCategorySlug : _selectedCategory;

  String? get _effectiveCategoryLabel {
    final eff = _effectiveCategory;
    if (eff == null) return null;
    return _categories.firstWhere((c) => c.slug == eff, orElse: () => (name: eff, slug: eff, count: 0)).name;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Espera as categorias chegarem antes do 1º pedido de canais — garante
  /// que o filtro "Anime" já está disponível logo na abertura da página
  /// (em vez de arriscar uma corrida entre os dois pedidos em paralelo).
  Future<void> _bootstrap() async {
    await _loadCategories();
    await _load(1);
  }

  @override
  void dispose() {
    _disposed = true;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ChannelsSource.categories();
      if (_disposed) return;
      setState(() => _categories = cats);
    } catch (_) {
      // categorias são opcionais na UI
    }
  }

  Future<void> _load(int page) async {
    setState(() => _loading = true);
    try {
      final effective = _effectiveCategory;
      final res = await ChannelsSource.list(
        page: page,
        limit: _limit,
        category: effective,
        hasUser: _hasUser,
      );
      if (_disposed) return;
      // Quando o filtro efectivo é "Animation" só por causa do default (o
      // utilizador não escolheu nada à mão), o site restringe ainda por
      // cima aos canais com logo — réplica fiel de main/channels/page.tsx.
      // O total/paginação não reflectem este filtro extra (comportamento
      // conhecido do site, mantido igual de propósito).
      var channels = res.channels;
      if (_animeOnly && _search.isEmpty && _selectedCategory == null && effective != null) {
        channels = channels.where((c) => c.logo != null).toList();
      }
      setState(() {
        _channels = channels;
        _total = res.total;
        _totalPages = res.pages;
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (_disposed) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _onCategoryChanged(String? slug) async {
    _searchController.clear();
    setState(() {
      _search = '';
      _selectedCategory = slug;
      _animeOnly = false;
    });
    await _load(1);
  }

  /// Botão "Anime"/"Todos" — liga/desliga o default, sempre limpando a
  /// busca e a categoria manual (igual ao toggle do site).
  Future<void> _toggleAnimeOnly() async {
    _searchController.clear();
    setState(() {
      _search = '';
      _animeOnly = !_animeOnly;
      _selectedCategory = null;
    });
    await _load(1);
  }

  DateTime _lastSearchInput = DateTime.now();
  Future<void> _onSearchChanged(String q) async {
    _search = q;
    setState(() {});
    final now = DateTime.now();
    _lastSearchInput = now;
    if (q.trim().isEmpty) {
      await _load(1);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (_lastSearchInput != now || _disposed) return;

    setState(() => _searching = true);
    try {
      final res = await ChannelsSource.search(q.trim(), hasUser: _hasUser);
      if (_disposed) return;
      setState(() {
        _channels = res;
        _total = res.length;
        _totalPages = 1;
      });
    } catch (_) {
    } finally {
      if (!_disposed) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
    _load(1);
  }

  void _onChannelTap(ChannelListItem ch) {
    if (!_hasUser) { context.go('/auth/login'); return; }
    if (ch.locked || !ch.hasAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Canal premium. Assine para assistir.')));
      return;
    }
    if (ch.url == null || ch.url!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stream indisponível.')));
      return;
    }
    // O gate real (GET /api/channels/:id → {ok:true}/401/429) é chamado
    // dentro do WatchScreen antes de reproduzir; aqui só passamos os dados
    // já conhecidos do client-side (o gate não os devolve).
    context.push(
      '/main/watch/channel_${ch.id}',
      extra: ChannelNavData(name: ch.name, logo: ch.logo, url: ch.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _channels.isEmpty) {
      return const ChannelsGridSkeleton(count: 12);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.live_tv_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(context.t('channels.title'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: AppColors.cardBg,
                    title: Text(c.t('channels.infoTitle')),
                    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.t('channels.infoBody1'), style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5)),
                      const SizedBox(height: 10),
                      Text(c.t('channels.infoBody2'), style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5)),
                    ]),
                    actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('common.close')))],
                  ),
                ),
                child: const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
              ),
            ]),
            Text(
              '$_total ${context.t('channels.available')}${_effectiveCategoryLabel != null ? ' · $_effectiveCategoryLabel' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar canais...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (_search.isNotEmpty ? IconButton(icon: const Icon(Icons.close, size: 16), onPressed: _clearSearch) : null),
              ),
            ),
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(width: 8),
            _AnimeToggleChip(active: _animeOnly, onTap: _toggleAnimeOnly),
            const SizedBox(width: 8),
            _CategoryDropdown(categories: _categories, selected: _selectedCategory, onChanged: _onCategoryChanged),
          ],
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: _channels.isEmpty && !_loading
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.live_tv_outlined, size: 32, color: AppColors.textMuted),
                    const SizedBox(height: 10),
                    Text(_search.isNotEmpty ? 'Nenhum canal encontrado' : 'Nenhum canal disponível', style: const TextStyle(color: AppColors.textMuted)),
                  ]),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, childAspectRatio: 1.7, crossAxisSpacing: 10, mainAxisSpacing: 10,
                  ),
                  itemCount: _channels.length,
                  itemBuilder: (c, i) {
                    final ch = _channels[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _onChannelTap(ch),
                      child: Stack(fit: StackFit.expand, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ch.logo != null
                              ? CachedNetworkImage(imageUrl: ch.logo!, fit: BoxFit.cover,
                                  errorWidget: (c, u, e) => Container(color: AppColors.cardHover),
                                  placeholder: (c, u) => Container(color: AppColors.cardBg))
                              : Container(decoration: BoxDecoration(color: AppColors.cardHover, borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.live_tv, color: AppColors.textMuted, size: 28)),
                        ),
                        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                colors: [Colors.black.withOpacity(0.85), Colors.transparent])))),
                        Positioned(left: 10, right: 10, bottom: 8, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                          Text(ch.group, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.65))),
                        ])),
                        Positioned(top: 8, right: 8, child: ch.locked
                            ? Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.lock, size: 10, color: AppColors.textMuted), SizedBox(width: 3),
                                  Text('Premium', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                                ]))
                            : Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                child: const Text('AO VIVO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)))),
                      ]),
                    );
                  },
                ),
        ),
        if (_search.isEmpty && _totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: _page > 1 ? () => _load(_page - 1) : null, icon: const Icon(Icons.chevron_left)),
              Text('Pág. $_page / $_totalPages', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              IconButton(onPressed: _page < _totalPages ? () => _load(_page + 1) : null, icon: const Icon(Icons.chevron_right)),
            ]),
          ),
      ],
    );
  }
}

class _AnimeToggleChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _AnimeToggleChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : AppColors.cardBg,
          border: Border.all(color: active ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            active ? 'Anime' : 'Todos',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: active ? AppColors.primary : AppColors.textLight),
          ),
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final List<({String name, String slug, int count})> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _CategoryDropdown({required this.categories, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selectedName = selected == null
        ? 'Todas as categorias'
        : categories.firstWhere((c) => c.slug == selected, orElse: () => (name: selected!, slug: selected!, count: 0)).name;

    return PopupMenuButton<String?>(
      onSelected: onChanged,
      itemBuilder: (c) => [
        const PopupMenuItem(value: null, child: Text('Todas as categorias')),
        const PopupMenuDivider(),
        ...categories.map((cat) => PopupMenuItem(
              value: cat.slug,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: Text(cat.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text('${cat.count}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            )),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: AppColors.cardBg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.live_tv, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: Text(selectedName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}
