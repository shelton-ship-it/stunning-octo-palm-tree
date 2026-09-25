import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'chacha20_segment.dart';

/// local_hls_proxy.dart — pendência #6 (player nativo sem WebView, "a maior").
///
/// O ExoPlayer (usado por baixo do `video_player`) já sabe tocar HLS/fMP4
/// nativamente — é exactamente isso que os canais ao vivo já fazem, sem
/// WebView, sem DRM. O que falta para o VOD é só a decifra: os segmentos
/// `.bin` do StreamVault vêm cifrados com ChaCha20 num formato próprio
/// ("chunk-v2" — ver ChaCha20Segment, porte fiel de workers/decrypt.worker.ts),
/// que o ExoPlayer não sabe interpretar sozinho, e não há nenhum ponto de
/// extensão do `video_player`/ExoPlayer para interceptar bytes em Dart.
///
/// Em vez de reimplementar o parsing HLS em Dart (a tentativa anterior,
/// documentada no topo de watch_screen.dart, falhou exactamente por essa
/// via — reimplementação paralela do hls.js/BinLoader), este proxy HTTP
/// local faz apenas o mínimo necessário e deixa o ExoPlayer fazer o resto
/// (buffering, ABR, demux, render) exactamente como já faz com os canais:
///
///   1. Busca a master.m3u8 REAL (a mesma URL que o ShakaPlayer.tsx usa) e
///      reescreve cada URI de segmento — incluindo `#EXT-X-MAP` (init.bin)
///      — para apontar para este servidor local.
///   2. Ao servir um segmento reescrito, busca o `.bin` cifrado original e
///      devolve-o já decifrado (fMP4 puro) — usando o MESMO algoritmo já
///      validado em produção para downloads offline (ChaCha20Segment).
///
/// Só escuta em 127.0.0.1, numa porta aleatória, uma instância por sessão
/// de reprodução — nenhum byte cifrado nem decifrado sai do aparelho.
class LocalHlsProxy {
  LocalHlsProxy._(this._server, this._originPlaylistUri, this._key);

  final HttpServer _server;
  final Uri _originPlaylistUri;
  final Uint8List _key;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 15),
  ));

  String get localMasterUrl => 'http://127.0.0.1:${_server.port}/master.m3u8';

  static Future<LocalHlsProxy> start({
    required String masterUrl,
    required String drmKeyHex,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    final proxy = LocalHlsProxy._(server, Uri.parse(masterUrl), ChaCha20Segment.hexToBytes(drmKeyHex));
    server.listen(proxy._handle, onError: (_) {}, cancelOnError: false);
    return proxy;
  }

  Future<void> stop() async {
    try {
      await _server.close(force: true);
    } catch (_) {
      // já fechado — ignora
    }
    _dio.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/master.m3u8':
          await _servePlaylist(request);
          break;
        case '/seg':
          await _serveSegment(request);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // resposta já fechada/abortada pelo cliente (ExoPlayer cancelou o
        // pedido) — nada a fazer.
      }
    }
  }

  /// Busca a m3u8 real e reescreve cada referência a segmento para uma URL
  /// local (`/seg?u=<original absoluta>`). Suporta tanto `#EXT-X-MAP:URI=`
  /// (init.bin) como as linhas de segmento normais (#EXTINF seguido do
  /// URI). URIs relativos (ex. `hls/seg00000.bin`) são resolvidos contra a
  /// URL real da playlist, exactamente como o hls.js faz antes de chamar o
  /// loader — por isso o BinLoader real só vê `.bin` já absolutos.
  Future<void> _servePlaylist(HttpRequest request) async {
    final res = await _dio.get<String>(
      _originPlaylistUri.toString(),
      options: Options(responseType: ResponseType.plain, headers: {'Accept': '*/*'}),
    );
    final body = res.data ?? '';

    final out = StringBuffer();
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trimRight();
      if (line.startsWith('#EXT-X-MAP')) {
        out.writeln(_rewriteMapLine(line));
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        out.writeln(_rewriteUri(line.trim()));
      } else {
        out.writeln(line);
      }
    }

    request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.write(out.toString());
    await request.response.close();
  }

  String _rewriteMapLine(String line) {
    final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
    if (match == null) return line;
    final rewritten = _rewriteUri(match.group(1)!);
    return line.replaceRange(match.start, match.end, 'URI="$rewritten"');
  }

  String _rewriteUri(String uri) {
    final resolved = _originPlaylistUri.resolve(uri);
    return '/seg?u=${Uri.encodeComponent(resolved.toString())}';
  }

  /// Busca o `.bin` cifrado original e devolve-o decifrado. Erros de rede
  /// e segmentos corrompidos/vazios respondem com um HTTP de erro explícito
  /// (nunca um corpo 200 vazio) — para o ExoPlayer tratar como falha de
  /// carregamento real (visível/retentável), nunca como "sucesso" silencioso
  /// que resultaria num ecrã vazio sem pista do que aconteceu.
  Future<void> _serveSegment(HttpRequest request) async {
    final target = request.uri.queryParameters['u'];
    if (target == null || target.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final Uint8List cipherBytes;
    try {
      cipherBytes = await _fetchWithRetry(target);
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    final plain = ChaCha20Segment.decryptSegment(cipherBytes, _key);
    if (plain.isEmpty) {
      request.response.statusCode = 422; // Unprocessable Entity
      await request.response.close();
      return;
    }

    request.response.headers.contentType = ContentType('video', 'mp4');
    request.response.headers.contentLength = plain.length;
    request.response.add(plain);
    await request.response.close();
  }

  Future<Uint8List> _fetchWithRetry(String url) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Accept': 'application/octet-stream'},
          ),
        );
        return Uint8List.fromList(res.data ?? const []);
      } catch (e) {
        lastErr = e;
        if (attempt < 2) await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw lastErr ?? Exception('fetch failed: $url');
  }
}
