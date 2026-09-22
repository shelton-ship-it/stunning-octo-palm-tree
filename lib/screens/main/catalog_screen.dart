import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/content_card.dart';

const _types = ['All', 'movie', 'series', 'anime', 'documentary', 'dorama'];

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _type = 'All';
  String _sort = 'recent';
  int _page = 1;
  final int _limit = 24;
  List<ContentItem> _items = [];
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'sort': _sort, 'page': _page, 'limit': _limit};
      if (_type != 'All') params['type'] = _type;
      final res = await catalogApi.list(params);
      final items = (res['items'] as List? ?? []).map((e) => ContentItem.fromJson(e)).toList();
      setState(() {
        _items = items;
        _total = res['pagination']?['total'] ?? items.length;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addToList(ContentItem item) async {
    final profiles = ref.read(authProvider).profiles;
    if (profiles.isEmpty) return;
    try {
      await myListApi.add(profiles.first.id, item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} — ${context.t('myList.added')}'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('common.error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = (_total / _limit).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('catalog.title'), style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _types.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (c, i) {
              final tp = _types[i];
              final active = _type == tp;
              return ChoiceChip(
                label: Text(context.t('catalog.${tp == 'All' ? 'allTypes' : tp}')),
                selected: active,
                onSelected: (_) {
                  setState(() { _type = tp; _page = 1; });
                  _load();
                },
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.cardBg,
                labelStyle: TextStyle(color: active ? Colors.white : AppColors.textMuted, fontSize: 12),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _items.isEmpty
                  ? Center(child: Text(context.t('catalog.noContent'), style: const TextStyle(color: AppColors.textMuted)))
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (c, i) => ContentCardWidget(
                        item: _items[i],
                        onTap: () => context.go('/main/content/${_items[i].id}'),
                        onAddToList: () => _addToList(_items[i]),
                      ),
                    ),
        ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Pág. $_page / $pages', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                IconButton(
                  onPressed: _page < pages ? () { setState(() => _page++); _load(); } : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
