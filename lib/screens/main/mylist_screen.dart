import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/content_card.dart';

class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});
  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  bool _loading = true;
  List<ContentItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = ref.read(authProvider).profiles;
    if (profiles.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await myListApi.list({'profileId': profiles.first.id, 'limit': 100});
      final entries = (res['items'] as List? ?? []);
      setState(() {
        _items = entries
            .where((e) => e['content'] != null)
            .map((e) => ContentItem.fromJson(e['content']))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.bookmark_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('myList.title'), style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${_items.length} ${context.t('myList.saved')}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.bookmark_outline, size: 32, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        Text(context.t('myList.empty')),
                        const SizedBox(height: 4),
                        Text(context.t('myList.emptyDesc'),
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: () => context.go('/main/catalog'),
                          child: Text(context.t('myList.browse')),
                        ),
                      ]),
                    )
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
                      ),
                    ),
        ),
      ],
    );
  }
}
