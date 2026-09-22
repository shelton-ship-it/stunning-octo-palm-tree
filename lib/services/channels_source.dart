import 'dart:convert';
import 'package:dio/dio.dart';

/// channels_source.dart — porte fiel de lib/channels-source.ts (pixel.zip).
/// A listagem de canais é 100% client-side: o app busca playlist.m3u +
/// logos.json directamente no jsDelivr (mirror público do repo GitHub
/// shelton-ship-it/assets-main) e faz o parsing/paginação/categoria/busca
/// aqui — o backend (routes/channels.js) só serve o "gate" de anti-abuso
/// (ChannelsApi.get/heartbeat), não conhece a lista de canais.
class RawChannel {
  final String id, name, url, logo, group, country, language, tvgId;
  RawChannel({
    required this.id,
    required this.name,
    required this.url,
    required this.logo,
    required this.group,
    required this.country,
    required this.language,
    required this.tvgId,
  });
}

class ChannelListItem {
  final String id, name, group;
  final String? logo, country, url;
  final bool locked, hasAccess;
  ChannelListItem({
    required this.id,
    required this.name,
    required this.group,
    this.logo,
    this.country,
    this.url,
    required this.locked,
    required this.hasAccess,
  });
}

class ChannelsSource {
  ChannelsSource._();
  static const _playlistUrl = 'https://cdn.jsdelivr.net/gh/shelton-ship-it/assets-main@main/playlist.m3u';
  static const _logosUrl = 'https://cdn.jsdelivr.net/gh/shelton-ship-it/assets-main@main/logos.json';
  static const _cacheTtl = Duration(minutes: 30);

  static List<RawChannel>? _cache;
  static DateTime? _cacheTime;
  static Future<List<RawChannel>>? _fetching;
  static final _dio = Dio();

  static List<RawChannel> _parseM3U(String text, Map<String, dynamic> logos) {
    final channels = <RawChannel>[];
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    Map<String, String>? current;
    int index = 0;

    String attr(String line, String name) {
      final r = RegExp('$name="([^"]*)"').firstMatch(line);
      return r?.group(1) ?? '';
    }

    for (final line in lines) {
      if (line.startsWith('#EXTINF')) {
        index++;
        final ci = line.lastIndexOf(',');
        current = {
          'id': 'ch_$index',
          'name': ci != -1 ? line.substring(ci + 1).trim() : '',
          'url': '',
          'logo': attr(line, 'tvg-logo'),
          'group': attr(line, 'group-title').isNotEmpty ? attr(line, 'group-title') : 'outros',
          'tvg_id': attr(line, 'tvg-id'),
          'country': attr(line, 'tvg-country'),
          'language': attr(line, 'tvg-language'),
        };
      } else if (current != null && !line.startsWith('#')) {
        current['url'] = line;
        if ((current['logo'] ?? '').isEmpty) {
          final tvgId = current['tvg_id'] ?? '';
          if (tvgId.isNotEmpty && logos[tvgId] != null) current['logo'] = logos[tvgId].toString();
        }
        if ((current['name'] ?? '').isNotEmpty && (current['url'] ?? '').isNotEmpty) {
          channels.add(RawChannel(
            id: current['id']!,
            name: current['name']!,
            url: current['url']!,
            logo: current['logo'] ?? '',
            group: current['group'] ?? 'outros',
            country: current['country'] ?? '',
            language: current['language'] ?? '',
            tvgId: current['tvg_id'] ?? '',
          ));
        }
        current = null;
      }
    }
    return channels;
  }

  static Future<List<RawChannel>> _fetchAndParse() async {
    final results = await Future.wait([
      _dio.get<String>(_playlistUrl, options: Options(responseType: ResponseType.plain)),
      _dio.get(_logosUrl).catchError((_) => Response(requestOptions: RequestOptions(path: _logosUrl), data: {})),
    ]);
    final playlistRes = results[0];
    if ((playlistRes.statusCode ?? 0) >= 400) {
      throw Exception('M3U respondeu ${playlistRes.statusCode}');
    }
    final playlistText = playlistRes.data ?? '';
    dynamic logosData = results[1].data;
    if (logosData is String) {
      try {
        logosData = jsonDecode(logosData);
      } catch (_) {
        logosData = {};
      }
    }
    final logos = (logosData is Map<String, dynamic>) ? logosData : <String, dynamic>{};
    return _parseM3U(playlistText, logos);
  }

  static Future<List<RawChannel>> _getRaw() async {
    final now = DateTime.now();
    if (_cache != null && _cacheTime != null && now.difference(_cacheTime!) < _cacheTtl) {
      return _cache!;
    }
    if (_fetching != null) return _fetching!;
    _fetching = _fetchAndParse().then((channels) {
      _cache = channels;
      _cacheTime = DateTime.now();
      return channels;
    }).whenComplete(() => _fetching = null);
    return _fetching!;
  }

  /// Deduplicação por nome (case-insensitive) — a playlist agregada de
  /// múltiplas fontes frequentemente repete o mesmo canal.
  static List<RawChannel> _dedupe(List<RawChannel> channels) {
    final seen = <String>{};
    final out = <RawChannel>[];
    for (final ch in channels) {
      final key = ch.name.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(ch);
    }
    return out;
  }

  static ChannelListItem _mapForList(RawChannel ch, bool hasUser) => ChannelListItem(
        id: ch.id,
        name: ch.name,
        group: ch.group,
        logo: ch.logo.isNotEmpty ? ch.logo : null,
        country: ch.country.isNotEmpty ? ch.country : null,
        locked: !hasUser,
        hasAccess: hasUser,
        url: hasUser ? ch.url : null,
      );

  static Future<({List<ChannelListItem> channels, int total, int pages, int grandTotal})> list({
    int page = 1,
    int limit = 24,
    String? category,
    required bool hasUser,
  }) async {
    final all = await _getRaw();
    final dedupedAll = _dedupe(all);
    final filtered = category != null
        ? dedupedAll.where((ch) => ch.group.toLowerCase() == category.toLowerCase()).toList()
        : dedupedAll;
    final total = filtered.length;
    final offset = (page - 1) * limit;
    final paginated = filtered.skip(offset).take(limit).map((ch) => _mapForList(ch, hasUser)).toList();
    return (
      channels: paginated,
      total: total,
      pages: (total / limit).ceil().clamp(1, 1 << 30),
      grandTotal: dedupedAll.length,
    );
  }

  static Future<List<({String name, String slug, int count})>> categories() async {
    final all = await _getRaw();
    final map = <String, int>{};
    for (final ch in all) {
      final g = ch.group.isNotEmpty ? ch.group : 'outros';
      map[g] = (map[g] ?? 0) + 1;
    }
    final entries = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => (name: e.key, slug: e.key.toLowerCase(), count: e.value)).toList();
  }

  static Future<List<ChannelListItem>> search(String query, {required bool hasUser}) async {
    final all = await _getRaw();
    final q = query.toLowerCase().trim();
    var filtered = all;
    if (q.isNotEmpty) {
      filtered = all.where((ch) =>
          ch.name.toLowerCase().contains(q) ||
          ch.group.toLowerCase().contains(q) ||
          ch.country.toLowerCase().contains(q) ||
          ch.language.toLowerCase().contains(q)).toList();
    }
    return filtered.take(200).map((ch) => _mapForList(ch, hasUser)).toList();
  }
}
