import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'chacha20_segment.dart';
import 'downloads_service.dart';
import 'api_client.dart';

/// download_manager.dart — orquestra o download offline: chama o
/// manifesto real (GET /content/:id/download), busca init+segmentos
/// (.bin, sem Authorization — mesma CDN pública do streaming), decifra
/// com [ChaCha20Segment] usando drm_key_hex, e escreve tudo, em ordem,
/// num único ficheiro .mp4 local (ver downloads_service.dart).
///
/// Esta peça não existia antes desta rodada — content_detail_screen.dart
/// tinha um separador "Downloads" que nunca era alcançável, porque nada
/// no projecto chamava GET /content/:id/download nem decifrava nada.
class DownloadProgress {
  final int done;
  final int total;
  DownloadProgress(this.done, this.total);
  double get fraction => total == 0 ? 0 : done / total;
}

class DownloadException implements Exception {
  final String message;
  final List<dynamic>? plans; // presente quando é 403 de cota esgotada
  DownloadException(this.message, {this.plans});
  @override
  String toString() => message;
}

class DownloadManager {
  static final _dio = Dio();

  /// downloadKey — identificador local do ficheiro (episódio quando
  /// aplicável, senão o próprio contentId; mesma convenção do `contentId`
  /// devolvido dentro de `manifest` pelo backend).
  static Future<void> download({
    required String contentId,
    String? episodeId,
    required String title,
    String? poster,
    void Function(DownloadProgress)? onProgress,
  }) async {
    Map<String, dynamic> data;
    try {
      data = await contentApi.getDownload(contentId, episodeId: episodeId);
    } on ApiException catch (e) {
      if (e.status == 403) {
        throw DownloadException(
          e.data?['message']?.toString() ?? 'Download não disponível.',
          plans: e.data?['plans'] as List?,
        );
      }
      rethrow;
    }

    final manifest = data['manifest'] as Map<String, dynamic>;
    final downloadKey = manifest['contentId']?.toString() ?? episodeId ?? contentId;
    final encrypted = manifest['encrypted'] == true;
    final drmKeyHex = data['drm_key_hex']?.toString();
    final key = (encrypted && drmKeyHex != null && drmKeyHex.isNotEmpty)
        ? ChaCha20Segment.hexToBytes(drmKeyHex)
        : null;

    final initUrl = manifest['initUrl']?.toString();
    final segUrls = ((manifest['segUrls'] as List?) ?? []).cast<String>();
    final total = 1 + segUrls.length; // init + segmentos

    final tempPath = await DownloadsService.instance.tempFilePath(downloadKey);
    final tempFile = File(tempPath);
    final sink = tempFile.openWrite();
    var done = 0;
    try {
      if (initUrl != null) {
        final bytes = await _fetchBin(initUrl);
        sink.add(key != null ? ChaCha20Segment.decryptSegment(bytes, key) : bytes);
        done++;
        onProgress?.call(DownloadProgress(done, total));
      }
      for (final url in segUrls) {
        final bytes = await _fetchBin(url);
        sink.add(key != null ? ChaCha20Segment.decryptSegment(bytes, key) : bytes);
        done++;
        onProgress?.call(DownloadProgress(done, total));
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }

    final finalPath = await DownloadsService.instance.localFilePath(downloadKey);
    await tempFile.rename(finalPath);

    final expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 30));

    await DownloadsService.instance.saveMeta(
      contentId: downloadKey,
      title: title,
      poster: poster,
      quality: encrypted ? 'original' : 'direct',
      expiresAt: expiresAt,
      localPath: finalPath,
    );
  }

  /// .bin público (CDN raw.githubusercontent.com) — mesma chamada sem
  /// Authorization que o player faz para streaming (ver ShakaPlayer.tsx).
  static Future<Uint8List> _fetchBin(String url) async {
    final res = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Accept': 'application/octet-stream'},
      ),
    );
    return Uint8List.fromList(res.data ?? const []);
  }
}
