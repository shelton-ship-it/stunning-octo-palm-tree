import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../widgets/content_card.dart';

/// SearchScreen — réplica exata do contrato usado em app/main/search/page.tsx:
/// searchApi.search(query, {limit:24}) → res.results / res.pagination?.total.
/// Sem chaves alternativas "por garantia" — é o mesmo contrato já testado
/// no site, ponto final.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ContentItem> _results = [];
  List<String> _popular = [];
  bool _loading = false;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    searchApi.popular().then((p) {
      if (!mounted) return;
      setState(() => _popular = p.map((e) => cleanStr(e['term'])).whereType<String>().toList());
    }).catchError((e) {
      if (kDebugMode) debugPrint('searchApi.popular falhou: $e');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _results = []; _total = 0; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 340), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _loading = true);
    try {
      final res = await searchApi.search(q, {'limit': 24});
      final items = (res['results'] as List? ?? []).map((e) => ContentItem.fromJson(e)).toList();
      if (!mounted) return;
      setState(() {
        _results = items;
        _total = res['pagination']?['total'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('searchApi.search falhou: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('search.title'), style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: context.t('search.placeholder'),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
        ),
        const SizedBox(height: 16),
        if (_controller.text.trim().isEmpty && _popular.isNotEmpty) ...[
          Row(children: [
            const Icon(Icons.trending_up, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(context.t('search.popularSearches'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _popular.map((term) => ActionChip(
              label: Text(term, style: const TextStyle(fontSize: 12)),
              backgroundColor: AppColors.cardBg,
              onPressed: () { _controller.text = term; _onChanged(term); },
            )).toList(),
          ),
        ],
        if (_controller.text.trim().isNotEmpty)
          Expanded(
            child: _results.isEmpty && !_loading
                ? Center(child: Text(context.t('common.noResults'), style: const TextStyle(color: AppColors.textMuted)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_total ${context.t('search.results')} "${_controller.text}"', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.52,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: _results.length,
                          itemBuilder: (c, i) => ContentCardWidget(
                            item: _results[i],
                            onTap: () => context.go('/main/content/${_results[i].id}'),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
