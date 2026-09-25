import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/content_card.dart';
import '../../widgets/skeletons.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loading = true;
  List<ContentItem> _featured = [];
  List<ContentItem> _movies = [];
  List<ContentItem> _series = [];
  List<ContentItem> _anime = [];
  List<ContentItem> _popular = [];
  int _heroIdx = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// GET /catalog/home — porte 1:1 do que a home real do pixel usa: UM
  /// único pedido, que já vem com featured/popular/latest agrupados (e já
  /// aplica o filtro de perfil infantil no servidor via profile_id). A
  /// versão anterior fazia 5 pedidos separados (featured+3×latest+list)
  /// para montar a mesma coisa.
  Future<void> _load() async {
    try {
      final profiles = ref.read(authProvider).profiles;
      final profileId = profiles.isNotEmpty ? profiles.first.id : null;
      final res = await catalogApi.home(profileId);
      final latest = (res['latest'] as Map<String, dynamic>?) ?? {};
      List<ContentItem> parse(dynamic list) =>
          ((list as List?) ?? []).map((e) => ContentItem.fromJson(e as Map<String, dynamic>)).toList();
      setState(() {
        _featured = parse(res['featured']);
        _popular = parse(res['popular']);
        _movies = parse(latest['movie']);
        _series = parse(latest['series']);
        _anime = parse(latest['anime']);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          HeroSkeleton(),
          SizedBox(height: 20),
          ContentGridSkeleton(count: 9),
        ]),
      );
    }
    final hasAny = _featured.isNotEmpty || _movies.isNotEmpty || _series.isNotEmpty || _anime.isNotEmpty;
    if (!hasAny) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.tv_off_rounded, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(context.t('home.noContent')),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: _load, child: Text(context.t('common.retry'))),
        ]),
      );
    }

    final hero = _featured.isNotEmpty ? _featured[_heroIdx % _featured.length] : null;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (hero != null) _buildHero(hero),
          const SizedBox(height: 18),
          _buildRow(context.t('home.popularNow'), _popular),
          _buildRow(context.t('home.latestMovies'), _movies),
          _buildRow(context.t('home.series'), _series),
          _buildRow(context.t('home.anime'), _anime),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHero(ContentItem hero) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: hero.poster != null
                ? CachedNetworkImage(imageUrl: hero.poster!, fit: BoxFit.cover)
                : Container(color: AppColors.cardBg),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16, right: 16, bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(hero.type ?? '').toUpperCase()}${hero.year != null ? ' · ${hero.year}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  hero.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  ElevatedButton.icon(
                    onPressed: () => context.push('/main/watch/${hero.id}'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(context.t('home.playNow')),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/main/content/${hero.id}'),
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    label: Text(context.t('home.moreInfo')),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, List<ContentItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (c, i) => SizedBox(
                width: 128,
                child: ContentCardWidget(
                  item: items[i],
                  onTap: () => context.go('/main/content/${items[i].id}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
