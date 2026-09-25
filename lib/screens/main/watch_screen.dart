import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:chewie/chewie.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/download_manager.dart';
import '../../services/downloads_service.dart';
import '../../services/ecdh_keygen.dart';
import '../../services/local_hls_proxy.dart';
import '../../widgets/plan_modals.dart';

/// WatchScreen — equivalente a watch/[id]/page.tsx (VOD) e ChannelPlayer.tsx (TV).
///
/// FIX v5 — PLAYER NATIVO SEM WEBVIEW (pendência #6):
/// As tentativas anteriores (proxy nativo com ChaCha20 em Dart reimplementando
/// o parsing HLS, depois uma WebView apontada para o ShakaPlayer.tsx real)
/// tinham problemas próprios — a primeira reimplementava lógica paralela ao
/// hls.js/BinLoader (frágil), a segunda dependia de uma WebView (não é o
/// pedido: "sem simplesmente incorporar o frontend dentro de uma WebView").
///
/// Esta versão usa o ExoPlayer nativo (via `video_player`, o MESMO motor já
/// usado pelos canais ao vivo, sem WebView nenhuma) para tudo — VOD, canal e
/// offline. A única peça que faltava para o VOD é a decifra dos segmentos
/// `.bin` (ChaCha20, formato "chunk-v2") — resolvida por [LocalHlsProxy]: um
/// servidor HTTP local (127.0.0.1, porta aleatória) que busca a m3u8 real,
/// reescreve as referências a segmento, e devolve cada `.bin` já decifrado —
/// usando o MESMO algoritmo (ChaCha20Segment) já validado em produção para
/// os downloads offline. O handshake ("ECDH") é feito directamente por este
/// ecrã (ver ecdh_keygen.dart + ContentApi.stream), reproduzindo fielmente
/// performECDH() do ShakaPlayer.tsx: o servidor devolve `drm_key_hex` em
/// claro, não há segredo nenhum a derivar no cliente.
///
/// TV ao vivo continua nativa (video_player/ExoPlayer directo, sem DRM —
/// streams IPTV públicos), com o MESMO gate + heartbeat de anti-abuso já
/// existente: GET /api/channels/:id antes de tocar (gate — devolve só
/// {ok:true}, não dados do canal, por isso o url/name/logo vêm de
/// [ChannelNavData], já conhecidos do client-side), depois POST heartbeat a
/// cada 120s enquanto toca.
class WatchScreen extends ConsumerStatefulWidget {
  final String id;
  final bool offline;
  final String? episodeId;
  final ChannelNavData? channelData;
  const WatchScreen({super.key, required this.id, this.offline = false, this.episodeId, this.channelData});

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> with WidgetsBindingObserver {
  // Player nativo — usado para TV ao vivo, VOD (via [LocalHlsProxy]) e offline.
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  // VOD — proxy HTTP local que decifra os segmentos .bin em tempo real
  // (ver local_hls_proxy.dart). null quando o conteúdo não é cifrado ou
  // quando é canal/offline.
  LocalHlsProxy? _hlsProxy;

  static const _initTimeout = Duration(seconds: 25);

  bool _loading = true;
  String? _error;
  String? _debugError;
  String _title = '';
  String? _poster;
  String? _channelLogo;
  String? _resolvedEpisodeId;
  String? _nextEpisodeId;
  List<ContentItem> _recommendations = [];
  bool get _isChannel => widget.id.startsWith('channel_');

  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _channelHeartbeat;
  Timer? _vodHeartbeat;
  bool _endedHandled = false;

  // "Próximo episódio em Xs" — réplica do autoNextIn do ShakaPlayer.tsx,
  // agora desenhado nativamente (antes vivia dentro da WebView).
  Timer? _autoNextTimer;
  int? _autoNextIn;

  // Download no player (pendência #12) — reaproveita DownloadManager, já
  // usado em content_detail_screen.dart.
  bool _downloadAvailable = false;
  bool _downloading = false;
  double _downloadPct = 0;
  bool _downloaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
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
      if (e.status == 429) {
        final plans = e.data is Map ? e.data['plans'] as List? : null;
        if (plans != null && plans.isNotEmpty) {
          RateLimitModal.show(context, plans: plans, message: e.data?['message']?.toString());
        }
      }
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFullscreenWithOrientation());
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFullscreenWithOrientation());
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
            final plans = e.data is Map ? e.data['plans'] as List? : null;
            if (plans != null && plans.isNotEmpty) {
              RateLimitModal.show(context, plans: plans, message: e.data?['message']?.toString());
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Limite gratuito de 1 hora atingido. Assine um plano para continuar.')),
              );
            }
          }
        }
      } catch (_) {
        // rede — ignora, tenta de novo no próximo tick
      }
    }

    send();
    _channelHeartbeat = Timer.periodic(const Duration(seconds: 120), (_) => send());
  }

  /// Heartbeat do VOD — porte fiel do sendHeartbeat() em ShakaPlayer.tsx
  /// (POST /api/content/:id/heartbeat a cada 120s enquanto toca, ver
  /// HEARTBEAT_MS lá). Mesmo tratamento de 409 (sessão substituída) e 429
  /// (limite diário) do heartbeat de canal.
  void _startVodHeartbeat() {
    Future<void> send() async {
      final v = _videoController;
      if (v == null || !v.value.isPlaying) return;
      try {
        await contentApi.heartbeat(widget.id, position: v.value.position.inSeconds, episodeId: _resolvedEpisodeId);
      } on ApiException catch (e) {
        if (e.status == 409) {
          _vodHeartbeat?.cancel();
          _vodHeartbeat = null;
          await _videoController?.pause();
          if (mounted) _showSessionReplaced(e.data?['message']?.toString());
        } else if (e.status == 429) {
          _vodHeartbeat?.cancel();
          _vodHeartbeat = null;
          await _videoController?.pause();
          if (mounted) {
            final plans = e.data is Map ? e.data['plans'] as List? : null;
            if (plans != null && plans.isNotEmpty) {
              RateLimitModal.show(context, plans: plans, message: e.data?['message']?.toString());
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Limite gratuito de 1 hora atingido. Assine um plano para continuar.')),
              );
            }
          }
        }
      } catch (_) {
        // rede — ignora, tenta de novo no próximo tick
      }
    }

    send();
    _vodHeartbeat = Timer.periodic(const Duration(seconds: 120), (_) => send());
  }

  void _showSessionReplaced(String? message) {
    SessionReplacedModal.show(context, message: message);
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

  /// VOD — pendência #6: handshake real (GET /content/:id/stream, mesmo
  /// endpoint/parâmetros do performECDH() em ShakaPlayer.tsx) + player
  /// nativo apontado para o [LocalHlsProxy] local, que decifra os
  /// segmentos .bin em tempo real. Zero WebView.
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
    _poster = cleanStr(meta is Map ? meta['poster'] : null) ?? cleanStr(content['poster']);
    final download = content['download'];
    _downloadAvailable = download is Map && download['available'] == true;

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

    final downloadKey = _resolvedEpisodeId ?? widget.id;
    final dl = await DownloadsService.instance.getDownload(downloadKey);
    if (dl != null) _downloaded = true;

    // Handshake real — o formato "ECDH" existe só para o backend validar a
    // chave pública (ver ecdh_keygen.dart); a resposta já traz drm_key_hex
    // em claro, exactamente como o site recebe.
    final pubKeyB64 = await generateEcdhClientPubKeyB64();
    final streamInfo = await contentApi.stream(widget.id, episodeId: episodeId, clientPubKeyB64: pubKeyB64);

    final masterUrl = cleanStr(streamInfo['master_url']) ?? cleanStr(streamInfo['url']);
    if (masterUrl == null || masterUrl.isEmpty) {
      throw Exception('Stream sem master_url');
    }
    final drmKeyHex = cleanStr(streamInfo['drm_key_hex']);

    final String playableUrl;
    if (drmKeyHex != null && drmKeyHex.isNotEmpty) {
      // Conteúdo cifrado (o caso normal) — sobe o proxy local que decifra
      // cada .bin em tempo real antes de o entregar ao ExoPlayer.
      _hlsProxy = await LocalHlsProxy.start(masterUrl: masterUrl, drmKeyHex: drmKeyHex);
      playableUrl = _hlsProxy!.localMasterUrl;
    } else {
      // Conteúdo não cifrado (playlist.encrypted === false no backend) —
      // o ExoPlayer toca a master_url directamente, sem proxy nenhum.
      playableUrl = masterUrl;
    }

    _videoController = VideoPlayerController.networkUrl(Uri.parse(playableUrl));
    _videoController!.addListener(_onPlaybackError);
    _videoController!.addListener(_onVodProgress);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFullscreenWithOrientation());
    _startVodHeartbeat();

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

  /// Grava o progresso (throttle de 15s, igual ao site) e detecta o fim do
  /// vídeo para disparar a contagem de "próximo episódio" — porte fiel do
  /// onTimeUpdate/onEnded do ShakaPlayer.tsx, agora sobre o
  /// VideoPlayerController nativo em vez de eventos do <video> da WebView.
  void _onVodProgress() {
    final v = _videoController;
    if (v == null || !mounted) return;
    final val = v.value;
    if (!val.isInitialized) return;

    _saveProgress(val.position.inMilliseconds / 1000.0, val.duration.inMilliseconds / 1000.0);

    if (!_endedHandled &&
        val.duration > Duration.zero &&
        val.position >= val.duration - const Duration(milliseconds: 400)) {
      _endedHandled = true;
      _onVodEnded();
    }
  }

  void _onVodEnded() {
    if (!mounted || _nextEpisodeId == null) return;
    setState(() => _autoNextIn = 5);
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final n = (_autoNextIn ?? 1) - 1;
      if (n <= 0) {
        _autoNextTimer?.cancel();
        _autoNextTimer = null;
        final next = _nextEpisodeId!;
        setState(() => _autoNextIn = null);
        _switchEpisode(next);
      } else {
        setState(() => _autoNextIn = n);
      }
    });
  }

  void _cancelAutoNext() {
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    if (mounted) setState(() => _autoNextIn = null);
  }

  /// Troca de episódio — substitui o ecrã actual por um WatchScreen novo já
  /// com o próximo episódio (mesmo padrão já usado pelo toque nas
  /// recomendações, abaixo), o que garante uma reinicialização limpa de
  /// todo o pipeline (handshake, proxy local, player).
  void _switchEpisode(String episodeId) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WatchScreen(id: widget.id, episodeId: episodeId)),
    );
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

  /// Botão de download no player (pendência #12) — reaproveita
  /// DownloadManager/DownloadsService tal como já usados em
  /// content_detail_screen.dart; a única novidade é expor a mesma ação
  /// aqui, no ecrã onde o utilizador já está a assistir.
  Future<void> _onDownloadTap() async {
    if (_downloading || _downloaded) return;
    setState(() { _downloading = true; _downloadPct = 0; });
    try {
      await DownloadManager.download(
        contentId: widget.id,
        episodeId: _resolvedEpisodeId,
        title: _title,
        poster: _poster,
        onProgress: (p) {
          if (mounted) setState(() => _downloadPct = p.fraction);
        },
      );
      if (!mounted) return;
      setState(() { _downloading = false; _downloaded = true; });
    } on DownloadException catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha ao descarregar. Tenta novamente.')));
    }
  }

  Future<void> _retry() async {
    await _teardownPlayer();
    await _init();
  }

  Future<void> _teardownPlayer() async {
    _channelHeartbeat?.cancel();
    _channelHeartbeat = null;
    _vodHeartbeat?.cancel();
    _vodHeartbeat = null;
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    _autoNextIn = null;
    _endedHandled = false;
    _videoController?.removeListener(_onPlaybackError);
    _videoController?.removeListener(_onVodProgress);
    _chewieController?.dispose();
    _chewieController = null;
    await _videoController?.dispose();
    _videoController = null;
    await _hlsProxy?.stop();
    _hlsProxy = null;
  }

  // ── Pendência #4 — fullscreen do player na rotação ────────────────────────
  // Réplica do comportamento pedido para os canais, mas aplica-se por igual
  // ao VOD e ao offline agora que todos usam o mesmo Chewie/ExoPlayer nativo
  // (antes o VOD vivia dentro da WebView, sem nenhum controlo nativo sobre
  // fullscreen). didChangeMetrics() dispara sempre que a orientação física
  // do aparelho muda — a Activity não é recriada (android:configChanges já
  // inclui orientation|screenSize no AndroidManifest.xml), por isso a
  // reprodução nunca reinicia por causa da rotação.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _syncFullscreenWithOrientation();
  }

  void _syncFullscreenWithOrientation() {
    if (!mounted) return;
    final chewie = _chewieController;
    if (chewie == null || _loading || _error != null) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    final isLandscape = logicalSize.width > logicalSize.height;
    if (isLandscape && !chewie.isFullScreen) {
      chewie.enterFullScreen();
    } else if (!isLandscape && chewie.isFullScreen) {
      chewie.exitFullScreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _channelHeartbeat?.cancel();
    _vodHeartbeat?.cancel();
    _autoNextTimer?.cancel();
    _videoController?.removeListener(_onPlaybackError);
    _videoController?.removeListener(_onVodProgress);
    _chewieController?.dispose();
    _videoController?.dispose();
    _hlsProxy?.stop();
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
          if (!_loading && _error == null && _videoController != null && _chewieController != null)
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio == 0 ? 16 / 9 : _videoController!.value.aspectRatio,
              child: Chewie(controller: _chewieController!),
            ),

          // Loading — só cobre a fase "a preparar" (handshake, buscar
          // detalhes do conteúdo, subir o proxy local, montar o URL).
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

          // Botão de download (#12) — só VOD online, e só quando o
          // conteúdo/plano permitir (mesma permissão de
          // content_detail_screen.dart, ver `download.available`).
          if (!_loading && _error == null && !_isChannel && !widget.offline && _downloadAvailable)
            Positioned(top: 4, right: 4, child: _buildDownloadButton()),

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

          // "Próximo episódio em Xs" — antes vivia dentro da WebView
          // (ShakaPlayer.tsx), agora é desenhado nativamente.
          if (_autoNextIn != null) _buildAutoNextOverlay(),
        ]);
  }

  Widget _buildDownloadButton() {
    if (_downloaded) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: Icon(Icons.download_done, color: AppColors.secondary, size: 22),
      );
    }
    if (_downloading) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: _downloadPct > 0 ? _downloadPct : null,
            color: AppColors.primary,
            backgroundColor: Colors.white24,
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.download_outlined, color: Colors.white),
      tooltip: 'Baixar para assistir offline',
      onPressed: _onDownloadTap,
    );
  }

  Widget _buildAutoNextOverlay() {
    return Positioned(
      bottom: 60, right: 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Próximo episódio em', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text('$_autoNextIn', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.primary, height: 1)),
          ]),
          const SizedBox(width: 14),
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ElevatedButton(
              onPressed: () {
                final next = _nextEpisodeId;
                _cancelAutoNext();
                if (next != null) _switchEpisode(next);
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
              child: const Text('Próximo', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: _cancelAutoNext,
              child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      ),
    );
  }
}
