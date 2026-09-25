import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/content_card.dart';
import '../../widgets/plan_modals.dart';
import '../../widgets/skeletons.dart';

/// CatalogScreen — porte 1:1 de app/main/catalog/page.tsx REAL (o site
/// confirma no próprio código que a versão anterior deste ficheiro estava
/// corrompida — cópia acidental de content/[id]/page.tsx — por isso esta
/// reconstrução usa só esta fonte, ignorando qualquer versão anterior).
const _types = ['all', 'video', 'movie', 'series', 'anime', 'documentary', 'dorama'];
const _kidTypes = ['anime', 'dorama'];

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _type = 'all';
  String _sort = 'recent'; // 'recent' | 'popular'
  int _page = 1;
  int _pages = 1;
  static const _limit = 24;
  List<ContentItem> _items = [];
  bool _loading = true;
  bool _kidSynced = false;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  bool get _isKid => ref.read(authProvider).activeProfile?.isKid ?? false;

  /// videoFirst() — reordena a MESMA resposta (sem pedido extra) para os
  /// itens type=='video' aparecerem primeiro na aba "Todos".
  List<ContentItem> _videoFirst(List<ContentItem> items) {
    final videos = items.where((i) => i.type == 'video').toList();
    final rest = items.where((i) => i.type != 'video').toList();
    return [...videos, ...rest];
  }

  Future<void> _load(int page) async {
    setState(() => _loading = true);
    try {
      final profileId = ref.read(authProvider).activeProfileId;
      final params = <String, dynamic>{'limit': _limit, 'page': page, 'sort': _sort};
      if (_type != 'all') params['type'] = _type;
      if (profileId != null) params['profile_id'] = profileId;
      final res = await catalogApi.list(params);
      final items = ((res['items'] as List?) ?? []).map((e) => ContentItem.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _items = _videoFirst(items);
        _pages = (res['pagination']?['pages'] as num?)?.toInt() ?? 1;
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _items = []; _loading = false; });
    }
  }

  void _setType(String t) {
    setState(() => _type = t);
    _load(1);
  }

  void _setSort(String s) {
    setState(() => _sort = s);
    _load(1);
  }

  @override
  Widget build(BuildContext context) {
    // Se o perfil activo for infantil e a aba actual não for permitida,
    // cai para 'anime' — mesmo comportamento do useEffect real.
    if (_isKid && !_kidTypes.contains(_type) && !_kidSynced) {
      _kidSynced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _setType('anime'));
    }
    final visibleTypes = _isKid ? _kidTypes : _types;
    final plan = ref.watch(authProvider).plan;
    final isPremium = plan != null && plan.id != 'free';

    Widget body = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('catalog.title'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...visibleTypes.map((tp) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _chip(context.t('catalog.${tp == 'all' ? 'allTypes' : tp}'), _type == tp, () => _setType(tp)),
                    )),
                const SizedBox(width: 16),
                _chip(context.t('catalog.sortRecent'), _sort == 'recent', () => _setSort('recent')),
                const SizedBox(width: 8),
                _chip(context.t('catalog.sortPopular'), _sort == 'popular', () => _setSort('popular')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const ContentGridSkeleton(count: 18)
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(children: [
                const Icon(Icons.tv_off_rounded, size: 28, color: AppColors.textMuted),
                const SizedBox(height: 10),
                Text(context.t('catalog.noContent'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(context.t('catalog.noContentDesc'), style: const TextStyle(fontSize: 12, color: AppColors.textMuted), textAlign: TextAlign.center),
              ]),
            )
          else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.52,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
              ),
              itemCount: _items.length,
              itemBuilder: (c, i) => ContentCardWidget(
                item: _items[i],
                onTap: () => context.push('/main/content/${_items[i].id}'),
                onAddToList: () {
                  // Fire-and-forget — igual ao site real (sem await, sem
                  // bloquear nada; erro é silencioso, tal como lá).
                  final profileId = ref.read(authProvider).activeProfileId;
                  if (profileId != null) myListApi.add(profileId, _items[i].id).catchError((_) {});
                },
              ),
            ),
            if (_pages > 1) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton(onPressed: _page > 1 ? () => _load(_page - 1) : null, child: Text(context.t('common.previous'))),
                  for (final n in _pageNumbers())
                    n == -1
                        ? const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…', style: TextStyle(color: AppColors.textMuted)))
                        : _chip('$n', n == _page, () => _load(n)),
                  OutlinedButton(onPressed: _page < _pages ? () => _load(_page + 1) : null, child: Text(context.t('common.next'))),
                ],
              ),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );

    // PlansModal — só no /catalog, só plano free, 1×/dia (pedido explícito
    // replicado do site real).
    if (!isPremium) body = PlansModalGate(child: body);
    return body;
  }

  List<int> _pageNumbers() {
    final nums = <int>[];
    for (var n = 1; n <= _pages; n++) {
      if (n == 1 || n == _pages || (n - _page).abs() <= 2) nums.add(n);
    }
    final out = <int>[];
    for (var i = 0; i < nums.length; i++) {
      if (i > 0 && nums[i] - nums[i - 1] > 1) out.add(-1);
      out.add(nums[i]);
    }
    return out;
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.cardBg,
        labelStyle: TextStyle(color: active ? Colors.white : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
        side: BorderSide(color: active ? AppColors.primary : AppColors.border),
      );
}
