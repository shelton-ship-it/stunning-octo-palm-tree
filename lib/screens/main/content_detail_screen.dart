import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/download_manager.dart';
import '../../services/downloads_service.dart';

class ContentDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const ContentDetailScreen({super.key, required this.id});

  @override
  ConsumerState<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends ConsumerState<ContentDetailScreen> {
  Map<String, dynamic>? _content;
  bool _loading = true;
  bool _inList = false;
  int _openSeason = 0;
  final Set<String> _downloaded = {};
  final Map<String, double> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await contentApi.get(widget.id);
      setState(() { _content = c; _loading = false; });
      final profiles = ref.read(authProvider).profiles;
      if (profiles.isNotEmpty) {
        final inList = await myListApi.check(widget.id, profileId: profiles.first.id).catchError((_) => false);
        if (mounted) setState(() => _inList = inList);
      }
      final dl = await DownloadsService.instance.getDownload(widget.id);
      if (dl != null && mounted) setState(() => _downloaded.add(widget.id));
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  /// Inicia o download — porte fiel de GET /content/:id/download (ver
  /// download_manager.dart). `key` é o contentId para conteúdo não
  /// episódico, ou o episodeId quando `episodeId` é passado.
  Future<void> _startDownload({String? episodeId, required String title, String? poster}) async {
    final key = episodeId ?? widget.id;
    if (_downloading.containsKey(key) || _downloaded.contains(key)) return;
    setState(() => _downloading[key] = 0);
    try {
      await DownloadManager.download(
        contentId: widget.id,
        episodeId: episodeId,
        title: title,
        poster: poster,
        onProgress: (p) {
          if (mounted) setState(() => _downloading[key] = p.fraction);
        },
      );
      if (!mounted) return;
      setState(() { _downloading.remove(key); _downloaded.add(key); });
    } on DownloadException catch (e) {
      if (!mounted) return;
      setState(() => _downloading.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _downloading.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha ao descarregar. Tenta novamente.')));
    }
  }

  /// Padrão otimista (pendência #10, Rodada 1) — porte fiel de toggleList()
  /// em main/content/[id]/page.tsx: a UI muda IMEDIATAMENTE (sem esperar a
  /// API), o pedido é disparado em paralelo (sem await), e só reverte + avisa
  /// se falhar de facto. Antes disto, a UI só actualizava DEPOIS da resposta
  /// da API (sensação de atraso a cada toque); agora é instantâneo, igual ao
  /// site.
  void _toggleList() {
    final profiles = ref.read(authProvider).profiles;
    if (profiles.isEmpty) return;
    final profileId = profiles.first.id;
    if (_inList) {
      setState(() => _inList = false);
      myListApi.remove(profileId, widget.id).catchError((_) {
        if (!mounted) return;
        setState(() => _inList = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha de rede. Tente novamente.')));
      });
    } else {
      setState(() => _inList = true);
      myListApi.add(profileId, widget.id).catchError((_) {
        if (!mounted) return;
        setState(() => _inList = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha de rede. Tente novamente.')));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.bgDark, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }
    if (_content == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(),
        body: const Center(child: Text('Conteúdo não encontrado', style: TextStyle(color: AppColors.textMuted))),
      );
    }

    final c = _content!;
    final meta = c['meta'] as Map<String, dynamic>? ?? {};
    final title = cleanStr(meta['title']) ?? cleanStr(c['title']) ?? cleanStr(meta['name']) ?? cleanStr(c['name']) ?? '';
    final poster = cleanStr(meta['poster']) ?? cleanStr(c['poster']);
    final desc = cleanStr(meta['description']) ?? cleanStr(c['description']) ?? '';
    final genres = ((meta['genres'] ?? c['genres']) as List?)?.cast<String>() ?? [];
    final year = cleanStr(c['year']);
    final type = cleanStr(c['type']) ?? '';
    final seasons = (c['seasons'] as List?) ?? [];
    final download = c['download'] as Map<String, dynamic>?;
    final downloadAvailable = download?['available'] == true;
    // FIX: 'dorama' passou a ser exibido como "Animações" e tratado como
    // conteúdo unitário na superfície (sem selector de temporadas/
    // episódios) — decisão só de UI, igual ao content/[id]/page.tsx do web;
    // a API continua a devolver seasons se existirem.
    final isEpisodic = seasons.isNotEmpty && type != 'dorama';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.bgDarker,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                if (poster != null)
                  CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover)
                else
                  Container(color: AppColors.cardBg),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [AppColors.bgDark, Colors.transparent],
                    ),
                  ),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(delegate: SliverChildListDelegate([
              Text(title, style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Row(children: [
                if (year != null) Text('$year', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                if (year != null) const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.forType(type).withOpacity(0.18), borderRadius: BorderRadius.circular(4)),
                  child: Text(context.t('catalog.$type'), style: TextStyle(fontSize: 10, color: AppColors.forType(type), fontWeight: FontWeight.w700)),
                ),
              ]),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: genres.take(3).map((g) => Chip(
                  label: Text(g, style: const TextStyle(fontSize: 10)),
                  backgroundColor: AppColors.cardBg,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )).toList()),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => context.push('/main/watch/${widget.id}'),
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text('Assistir'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _toggleList,
                    icon: Icon(_inList ? Icons.bookmark : Icons.bookmark_border, size: 18),
                    label: Text(_inList ? 'Na lista' : 'Minha Lista'),
                  ),
                  if (downloadAvailable && !isEpisodic) _downloadButton(key: widget.id, title: title, poster: poster),
                  OutlinedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '$kWebBase/main/content/${widget.id}'));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado!')));
                      }
                    },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Icon(Icons.share_outlined, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Sobre', style: TextStyle(fontFamily: AppTheme.fontDisplay, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              Text(desc, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
              if (isEpisodic) ...[
                const SizedBox(height: 22),
                const Text('Temporadas e Episódios', style: TextStyle(fontFamily: AppTheme.fontDisplay, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                ...List.generate(seasons.length, (si) {
                  final season = seasons[si] as Map<String, dynamic>;
                  final episodes = (season['episodes'] as List?) ?? [];
                  final open = _openSeason == si;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(children: [
                      InkWell(
                        onTap: () => setState(() => _openSeason = open ? -1 : si),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Temporada ${si + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Row(children: [
                              Text('${episodes.length} episódios', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              Icon(open ? Icons.expand_less : Icons.chevron_right, size: 18),
                            ]),
                          ]),
                        ),
                      ),
                      if (open)
                        ...episodes.map((ep) {
                          final epMap = ep as Map<String, dynamic>;
                          final epId = epMap['id']?.toString() ?? '';
                          final epTitle = cleanStr(epMap['title']) ?? 'Episódio';
                          return ListTile(
                            dense: true,
                            title: Text(epTitle, style: const TextStyle(fontSize: 12.5)),
                            leading: const Icon(Icons.play_circle_outline, color: AppColors.primary, size: 22),
                            trailing: downloadAvailable ? _downloadButton(key: epId, episodeId: epId, title: '$title — $epTitle', poster: poster, compact: true) : null,
                            onTap: () => context.push('/main/watch/${widget.id}?ep=$epId'),
                          );
                        }),
                    ]),
                  );
                }),
              ],
            ])),
          ),
        ],
      ),
    );
  }

  Widget _downloadButton({required String key, String? episodeId, required String title, String? poster, bool compact = false}) {
    if (_downloaded.contains(key)) {
      return Icon(Icons.download_done, size: compact ? 20 : 18, color: AppColors.secondary);
    }
    final progress = _downloading[key];
    if (progress != null) {
      return SizedBox(
        width: compact ? 20 : 18,
        height: compact ? 20 : 18,
        child: CircularProgressIndicator(strokeWidth: 2, value: progress > 0 ? progress : null, color: AppColors.primary),
      );
    }
    final onTap = () => _startDownload(episodeId: episodeId, title: title, poster: poster);
    if (compact) {
      return IconButton(icon: const Icon(Icons.download_outlined, size: 20), onPressed: onTap);
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
      child: const Icon(Icons.download_outlined, size: 18),
    );
  }
}
