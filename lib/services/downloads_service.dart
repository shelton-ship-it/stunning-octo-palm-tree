import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// downloads_service.dart — equivalente Dart de lib/downloads.ts.
/// O site usa IndexedDB (metadata + segmentos cifrados, decifrados on the
/// fly durante a reprodução offline). Aqui, como não há MSE/hls.js
/// disponível, os segmentos já saem decifrados de download_manager.dart e
/// são escritos, em ordem (init + todos os segNNNNN), num único ficheiro
/// .mp4 local — fragmentos fMP4 que partilham o mesmo init/moov
/// concatenam-se num ficheiro válido, reproduzível directamente pelo
/// video_player/ExoPlayer sem servidor local nenhum.
class DownloadsService {
  DownloadsService._();
  static final instance = DownloadsService._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'pixgo_downloads.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE downloads (
          contentId TEXT PRIMARY KEY,
          title TEXT,
          poster TEXT,
          quality TEXT,
          localPath TEXT,
          expiresAt TEXT,
          downloadedAt TEXT
        )
      '''),
    );
    return _db!;
  }

  Future<Directory> _downloadsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'downloads'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Caminho local determinístico do ficheiro final (.mp4) — usado tanto
  /// por download_manager.dart (para escrever) como pelo player offline
  /// (para reproduzir).
  Future<String> localFilePath(String downloadKey) async {
    final dir = await _downloadsDir();
    return p.join(dir.path, '$downloadKey.mp4');
  }

  /// Ficheiro temporário usado durante o download (evita expor um .mp4
  /// parcial/corrompido se a app fechar a meio) — só é renomeado para o
  /// caminho final quando download_manager.dart confirma que terminou.
  Future<String> tempFilePath(String downloadKey) async {
    final dir = await _downloadsDir();
    return p.join(dir.path, '$downloadKey.mp4.part');
  }

  Future<List<DownloadItem>> listDownloads() async {
    final db = await _database;
    final rows = await db.query('downloads');
    return rows
        .map((r) => DownloadItem(
              contentId: r['contentId'] as String,
              title: r['title'] as String? ?? '',
              poster: r['poster'] as String?,
              quality: r['quality'] as String? ?? '',
              expiresAt: DateTime.tryParse(r['expiresAt'] as String? ?? '') ?? DateTime.now(),
              localPath: r['localPath'] as String?,
            ))
        .toList();
  }

  Future<DownloadItem?> getDownload(String downloadKey) async {
    final db = await _database;
    final rows = await db.query('downloads', where: 'contentId = ?', whereArgs: [downloadKey]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return DownloadItem(
      contentId: r['contentId'] as String,
      title: r['title'] as String? ?? '',
      poster: r['poster'] as String?,
      quality: r['quality'] as String? ?? '',
      expiresAt: DateTime.tryParse(r['expiresAt'] as String? ?? '') ?? DateTime.now(),
      localPath: r['localPath'] as String?,
    );
  }

  Future<void> deleteDownload(String downloadKey) async {
    final db = await _database;
    await db.delete('downloads', where: 'contentId = ?', whereArgs: [downloadKey]);
    final path = await localFilePath(downloadKey);
    final f = File(path);
    if (await f.exists()) await f.delete();
    final tmp = File(await tempFilePath(downloadKey));
    if (await tmp.exists()) await tmp.delete();
  }

  Future<void> saveMeta({
    required String contentId,
    required String title,
    String? poster,
    required String quality,
    required DateTime expiresAt,
    required String localPath,
  }) async {
    final db = await _database;
    await db.insert(
      'downloads',
      {
        'contentId': contentId,
        'title': title,
        'poster': poster,
        'quality': quality,
        'localPath': localPath,
        'expiresAt': expiresAt.toIso8601String(),
        'downloadedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> purgeExpired() async {
    final all = await listDownloads();
    final now = DateTime.now();
    for (final d in all) {
      if (d.expiresAt.isBefore(now)) await deleteDownload(d.contentId);
    }
  }
}
