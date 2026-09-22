import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:chewie/chewie.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/downloads_service.dart';

/// WatchScreen — equivalente a watch/[id]/page.tsx (VOD) e ChannelPlayer.tsx (TV).
///
/// FIX v4 — REUTILIZAÇÃO REAL do player, não transcrição:
/// As duas tentativas anteriores (proxy nativo com ChaCha20 em Dart, depois
/// uma cópia manual do hls.js/BinLoader dentro de uma WebView local) tinham
/// o mesmo problema de fundo: eram reimplementações paralelas da lógica do
/// ShakaPlayer.tsx, sem garantia de paridade perfeita, e cada uma introduziu
/// bugs sutis (herança ES6 incorrecta, etc.) que o componente real no site
/// nunca tem — porque é o componente real, já testado em produção há
/// semanas.
///
/// Esta versão elimina a reimplementação por completo: o VOD carrega uma
/// WebView apontada directamente para $kWebBase/embed/watch/:id — a página
/// real do site (app/embed/watch/[id]/page.tsx) que renderiza o componente
/// `<ShakaPlayer>` REAL, SEM QUALQUER alteração à sua lógica interna. Corre
/// no domínio real (pixgo.qzz.io), que já está na allowlist de CORS da API
/// — o handshake ECDH e o heartbeat são feitos pelo próprio componente,
/// exactamente como no site, sem nenhum código nativo Dart a replicar isso.
///
/// TV ao vivo é nativo (video_player/ExoPlayer directo) — sem DRM (streams
/// IPTV públicos), mas com o MESMO gate + heartbeat de anti-abuso do VOD
/// (routes/channels.js + middleware/rate-limit.js): GET /api/channels/:id
/// antes de tocar (gate — devolve só {ok:true}, NÃO dados do canal, por
/// isso o url/name/logo vêm de [ChannelNavData], já conhecidos do
/// client-side), depois POST heartbeat a cada 120s enquanto toca.
class WatchScreen extends ConsumerStatefulWidget {
  final String id;
  final bool offline;
  final String? episodeId;
  final ChannelNavData? channelData;
  const WatchScreen({super.key, required this.id, this.offline = false, this.episodeId, this.channelData});

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  // TV ao vivo (nativo)
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  // VOD (WebView + /embed/watch/:id real)
  WebViewController? _webViewController;

  static const _initTimeout = Duration(seconds: 25);

  bool _loading = true;
  String? _error;
  String? _debugError;
  String _title = '';
  String? _channelLogo;
  String? _resolvedEpisodeId;
  String? _nextEpisodeId;
  List<ContentItem> _recommendations = [];
  bool get _isChannel => widget.id.startsWith('channel_');

  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _channelHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _debugError = null;
    });
    try {
      if (widget.offline) {
        await _initOffline();
      } else if (_isChannel) {
        await _initChannel().timeout(_initTimeout);
      } else {
        await _initVod().timeout(_initTimeout);
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Tempo esgotado ao ligar ao stream. Verifique a sua ligação e tente novamente.';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 429
            ? 'Limite gratuito de 1 hora atingido. Assine um plano para continuar.'
            : (e.status == 401
                ? 'Faça login para assistir.'
                : (e.status == 404
                    ? 'Conteúdo não encontrado.'
                    : (e.status != null && e.status! >= 500
                        ? 'O servidor de stream falhou (HTTP ${e.status}).'
                        : 'Falha ao carregar o stream.')));
        _debugError = 'ApiException ${e.status}: ${e.message}';
        _loading = false;
      });
      if (kDebugMode) debugPrint('WatchScreen ApiException: ${e.status} ${e.message}');
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = 'Falha ao carregar o stream.';
        _debugError = e.toString();
        _loading = false;
      });
      if (kDebugMode) debugPrint('WatchScreen error: $e\n$st');
    }
  }

  /// Reprodução offline — ficheiro local já decifrado por download_manager.dart
  /// (init+segmentos concatenados num único .mp4). Sem gate nem heartbeat:
  /// é exactamente o ponto de um download offline — funcionar sem rede.
  Future<void> _initOffline() async {
    final dl = await DownloadsService.instance.getDownload(widget.id);
    if (dl == null || dl.localPath == null || !await File(dl.localPath!).exists()) {
      if (!mounted) return;
      setState(() { _error = 'Download não encontrado neste dispositivo.'; _loading = false; });
      return;
    }
    _title = dl.title;
    _videoController = VideoPlayerController.file(File(dl.localPath!));
    _videoController!.addListener(_onPlaybackError);
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: AppColors.primary,
        handleColor: AppColors.primary,
        bufferedColor: Colors.white24,
        backgroundColor: Colors.white10,
      ),
    );
    if (mounted) setState(() => _loading = false);
  }

  /// TV ao vivo — gate real antes de reproduzir + URL já conhecida do
  /// client-side (ChannelsSource), igual a handleChannelClick em
  /// main/channels/page.tsx: GET /api/channels/:id só valida
  /// limite/quota (devolve {ok:true}), NÃO dados do canal.
  Future<void> _initChannel() async {
    final realId = widget.id.substring('channel_'.length);
    final nav = widget.channelData;

    _title = nav?.name ?? '';
    _channelLogo = nav?.logo;
    final url = nav?.url;

    if (url == null || url.isEmpty) {
      if (!mounted) return;
      setState(() { _error = 'Stream indisponível.'; _loading = false; });
      return;
    }

    // Gate — mesma validação de limite de ecrãs/quota diária que o /stream
    // do VOD faz. 429 → mensagem tratada no catch geral de _init().
    await channelsApi.get(realId);

    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController!.addListener(_onPlaybackError);
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: AppColors.primary,
        handleColor: AppColors.primary,
        bufferedColor: Colors.white24,
        backgroundColor: Colors.white10,
      ),
    );
    if (mounted) setState(() => _loading = false);
    _startChannelHeartbeat(realId);
  }

  /// Heartbeat do canal — porte fiel de main/channels/page.tsx: 1º envio
  /// imediato, depois a cada 120s (HEARTBEAT_INTERVAL_MS do backend),
  /// pulando o envio se o vídeo não estiver de facto a tocar. 409 (sessão
  /// substituída) pausa e mostra aviso; 429 (limite diário) pausa e manda
  /// para os planos; outros erros (rede) são ignorados, tenta de novo no
  /// próximo tick.
  void _startChannelHeartbeat(String realId) {
    Future<void> send() async {
      final v = _videoController;
      if (v == null || !v.value.isPlaying) return;
      try {
        await channelsApi.heartbeat(realId, position: v.value.position.inSeconds);
      } on ApiException catch (e) {
        if (e.status == 409) {
          _channelHeartbeat?.cancel();
          await _videoController?.pause();
          if (mounted) _showSessionReplaced(e.data?['message']?.toString());
        } else if (e.status == 429) {
          _channelHeartbeat?.cancel();
          await _videoController?.pause();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Limite gratuito de 1 hora atingido. Assine um plano para continuar.')),
            );
          }
        }
      } catch (_) {
        // rede — ignora, tenta de novo no próximo tick
      }
    }

    send();
    _channelHeartbeat = Timer.periodic(const Duration(seconds: 120), (_) => send());
  }

  void _showSessionReplaced(String? message) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Sessão encerrada'),
        content: Text(message ?? 'A sua sessão foi encerrada neste dispositivo.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  void _onPlaybackError() {
    final v = _videoController;
    if (v == null || !mounted || _error != null) return;
    final err = v.value.errorDescription;
    if (err == null) return;
    setState(() {
      _error = 'O reprodutor falhou ao processar o vídeo.';
      _debugError = 'VideoPlayerController error: $err';
      _loading = false;
    });
    if (kDebugMode) debugPrint('VideoPlayerController error: $err');
  }

  /// VOD — abre a WebView directamente no domínio real do site, na página
  /// /embed/watch/:id, que renderiza o ShakaPlayer.tsx real. Ver nota no
  /// topo da classe.
  Future<void> _initVod() async {
    final token = await ApiClient.instance.token;
    if (token == null) {
      if (!mounted) return;
      setState(() { _error = 'Faça login para assistir.'; _loading = false; });
      return;
    }

    final content = await contentApi.get(widget.id).catchError((_) => <String, dynamic>{});
    final meta = content['meta'];
    _title = cleanStr(meta is Map ? meta['title'] : null) ??
        cleanStr(content['title']) ??
        cleanStr(meta is Map ? meta['name'] : null) ??
        cleanStr(content['name']) ??
        '';
    final poster = cleanStr(meta is Map ? meta['poster'] : null) ?? cleanStr(content['poster']);

    // Auto-selecção do primeiro episódio para série/anime, replicando
    // fielmente allEps[0] em watch/[id]/page.tsx quando nenhum episódio é
    // passado explicitamente. 'dorama' fica de fora — tratado como
    // conteúdo unitário (ver content_detail_screen.dart).
    String? episodeId = widget.episodeId;
    final contentType = cleanStr(content['type']);
    final flatEpisodes = <String>[];
    if (contentType == 'series' || contentType == 'anime') {
      final seasons = (content['seasons'] as List?) ?? [];
      for (final s in seasons) {
        final episodes = (s is Map ? s['episodes'] as List? : null) ?? [];
        for (final ep in episodes) {
          final epId = cleanStr((ep as Map)['id']);
          if (epId != null) flatEpisodes.add(epId);
        }
      }
      episodeId ??= flatEpisodes.isNotEmpty ? flatEpisodes.first : null;
    }
    _resolvedEpisodeId = episodeId;
    if (episodeId != null && flatEpisodes.isNotEmpty) {
      final idx = flatEpisodes.indexOf(episodeId);
      if (idx != -1 && idx + 1 < flatEpisodes.length) _nextEpisodeId = flatEpisodes[idx + 1];
    }

    final embedUrl = _buildEmbedUrl(token: token, episodeId: episodeId, poster: poster, nextEpisodeId: _nextEpisodeId);

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);
    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(false);
    }

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    await controller.addJavaScriptChannel('PixgoBridge', onMessageReceived: _onBridgeMessage);
    await controller.loadRequest(Uri.parse(embedUrl));

    _webViewController = controller;
    if (mounted) setState(() => _loading = false);
    // A página embed mostra o próprio ecrã de loading/erro do ShakaPlayer.tsx
    // (idêntico ao site) — não duplicamos esse estado aqui.

    // Recomendações abaixo do player (estilo "a seguir" do YouTube) —
    // reaproveita a lógica de "populares" já existente (catalog/featured),
    // como pedido.
    catalogApi.featured(12).then((items) {
      if (!mounted) return;
      setState(() {
        _recommendations = items
            .map((e) => ContentItem.fromJson(e as Map<String, dynamic>))
            .where((c) => c.id != widget.id)
            .toList();
      });
    }).catchError((_) {});
  }

  String _buildEmbedUrl({required String token, String? episodeId, String? poster, String? nextEpisodeId, int startTime = 0}) {
    final qp = <String, String>{'token': token};
    if (episodeId != null) qp['episode'] = episodeId;
    if (poster != null) qp['poster'] = poster;
    if (nextEpisodeId != null) qp['nextEpisodeId'] = nextEpisodeId;
    if (startTime > 0) qp['startTime'] = '$startTime';
    return Uri.parse('$kWebBase/embed/watch/${widget.id}').replace(queryParameters: qp).toString();
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    if (!mounted) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (data['type'] as String?) {
      case 'progress':
        _saveProgress((data['currentTime'] as num?)?.toDouble() ?? 0, (data['duration'] as num?)?.toDouble() ?? 0);
        break;
      case 'next_episode':
        final nextId = cleanStr(data['episodeId']);
        if (nextId != null) _switchEpisode(nextId);
        break;
      case 'freetime_exhausted':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Limite gratuito de 1 hora atingido. Assine um plano para continuar.')),
        );
        break;
      case 'session_replaced':
        _showSessionReplaced(cleanStr(data['message']));
        break;
      case 'ended':
        break;
    }
  }

  /// Recarrega a WebView com o próximo episódio — a página embed já expõe
  /// onNextEpisode via o mesmo componente real; aqui só trocamos o URL.
  Future<void> _switchEpisode(String episodeId) async {
    final token = await ApiClient.instance.token;
    if (token == null || _webViewController == null) return;
    _resolvedEpisodeId = episodeId;
    final url = _buildEmbedUrl(token: token, episodeId: episodeId);
    await _webViewController!.loadRequest(Uri.parse(url));
  }

  void _saveProgress(double currentTimeSecs, double durationSecs) {
    final now = DateTime.now();
    if (now.difference(_lastProgressSave).inSeconds < 15) return;
    _lastProgressSave = now;

    if (durationSecs <= 0) return;
    final profiles = ref.read(authProvider).profiles;
    if (profiles.isEmpty) return;
    final pct = (currentTimeSecs / durationSecs) * 100;

    progressApi.update(
      profileId: profiles.first.id,
      contentId: widget.id,
      episodeId: _resolvedEpisodeId,
      progress: pct,
      duration: durationSecs.round(),
    ).catchError((_) {});
  }

  Future<void> _retry() async {
    await _teardownPlayer();
    await _init();
  }

  Future<void> _teardownPlayer() async {
    _channelHeartbeat?.cancel();
    _channelHeartbeat = null;
    _videoController?.removeListener(_onPlaybackError);
    _chewieController?.dispose();
    _chewieController = null;
    await _videoController?.dispose();
    _videoController = null;
    _webViewController = null;
  }

  @override
  void dispose() {
    _channelHeartbeat?.cancel();
    _videoController?.removeListener(_onPlaybackError);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Só mostra a secção de recomendações quando o VOD já carregou com
    // sucesso — evita competir com os ecrãs de loading/erro, e não se
    // aplica a canais ao vivo (TV não é "conteúdo a navegar").
    // Offline: sem rede fiável garantida, evita chamadas de rede extra
    // (recomendações) que poderiam falhar/travar — mesma cautela do canal.
    final showRecommendations = !_isChannel && !widget.offline && !_loading && _error == null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: showRecommendations
            ? Column(children: [
                AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerStack()),
                Expanded(child: _buildRecommendations()),
              ])
            : _buildPlayerStack(),
      ),
    );
  }

  Widget _buildRecommendations() {
    if (_recommendations.isEmpty) return const SizedBox.shrink();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _recommendations.length + 1,
      itemBuilder: (c, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Populares', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          );
        }
        final rec = _recommendations[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () {
              // Substitui o ecrã actual pelo novo conteúdo (evita empilhar
              // várias telas de watch ao navegar pelas recomendações).
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => WatchScreen(id: rec.id)),
              );
            },
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 128, height: 72,
                  child: rec.poster != null
                      ? CachedNetworkImage(imageUrl: rec.poster!, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: AppColors.bgDarker))
                      : Container(color: AppColors.bgDarker),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rec.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (rec.year != null)
                    Text('${rec.year}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildPlayerStack() {
    return Stack(children: [
          if (!_loading && _error == null)
            ((_isChannel || widget.offline)
                ? AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio == 0 ? 16 / 9 : _videoController!.value.aspectRatio,
                    child: Chewie(controller: _chewieController!),
                  )
                : (_webViewController != null ? WebViewWidget(controller: _webViewController!) : const SizedBox.shrink())),

          // Loading — só cobre a fase "a preparar" (buscar detalhes do
          // conteúdo, montar o URL). No VOD, assim que a WebView aparece, o
          // próprio ShakaPlayer.tsx mostra o seu ecrã de loading real.
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: SizedBox(
                  width: 40, height: 40,
                  child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary, backgroundColor: Colors.white24),
                ),
              ),
            ),

          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: AppColors.primary, size: 40),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  if (kDebugMode && _debugError != null) ...[
                    const SizedBox(height: 8),
                    Text(_debugError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                  ],
                  const SizedBox(height: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
                    const SizedBox(width: 12),
                    ElevatedButton(onPressed: _retry, child: const Text('Tentar novamente')),
                  ]),
                ]),
              ),
            ),

          if (!_loading && _error == null)
            Positioned(
              top: 8, left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

          // Canal ao vivo: logo + nome + badge "AO VIVO" + botão "Parar" —
          // réplica fiel do ChannelPlayer.tsx.
          if (!_loading && _error == null && _isChannel)
            Positioned(
              left: 16, bottom: 16,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                      colors: [Colors.black.withOpacity(0.7), Colors.black.withOpacity(0)],
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_channelLogo != null)
                      Container(
                        width: 36, height: 36,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2)),
                        clipBehavior: Clip.antiAlias,
                        child: CachedNetworkImage(imageUrl: _channelLogo!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
                      ),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(_title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, shadows: [Shadow(blurRadius: 2, color: Colors.black54)])),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFF0000), borderRadius: BorderRadius.circular(4)),
                        child: const Text('AO VIVO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          if (!_loading && _error == null && _isChannel)
            Positioned(
              right: 16, bottom: 16,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.75),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Parar'),
              ),
            ),

          if (!_loading && _error == null && !_isChannel && _title.isNotEmpty)
            Positioned(
              top: 8, left: 52, right: 12,
              child: Text(_title, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ]);
  }
}
