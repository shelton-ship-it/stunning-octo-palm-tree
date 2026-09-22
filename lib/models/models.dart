/// Sanitiza valores de string vindos da API: trata null, string vazia, e as
/// strings literais "undefined"/"null" (que por vezes vêm assim mesmo do
/// backend) como "sem valor" — evita que "undefined" apareça escrito nos ecrãs.
String? cleanStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final lower = s.toLowerCase();
  if (lower == 'undefined' || lower == 'null') return null;
  return s;
}

class AppUser {
  final String id;
  final String username;
  final String name;
  final String? email;
  final String role;
  final String planId;

  AppUser({
    required this.id,
    required this.username,
    required this.name,
    this.email,
    required this.role,
    required this.planId,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: cleanStr(j['id']) ?? '',
        username: cleanStr(j['username']) ?? '',
        name: cleanStr(j['name']) ?? '',
        email: cleanStr(j['email']),
        role: cleanStr(j['role']) ?? 'user',
        planId: cleanStr(j['plan_id']) ?? 'free',
      );
}

/// AppPlan — espelha o objeto real de GET /api/payments/plans
/// (lib/edgeone.js PLANS: id/name/price/label/max_profiles/max_downloads/
/// duration_days/billing_cycle/features). Ids públicos: free, monthly,
/// quarterly, annual. `price`/`label` só são informativos — o preço/moeda
/// reais de cobrança vêm sempre de GET /payments/gateway no momento do
/// checkout (decidido no servidor pelo país), nunca hardcoded no cliente.
class AppPlan {
  final String id;
  final String name;
  final double? price;
  final String? label;
  final bool isActive;
  final String? expiresAt;
  final int? durationDays;
  final int? maxProfiles;
  final int? maxDownloads; // null = ilimitado (plano anual)
  final List<String> features;

  AppPlan({
    required this.id,
    required this.name,
    this.price,
    this.label,
    this.isActive = false,
    this.expiresAt,
    this.durationDays,
    this.maxProfiles,
    this.maxDownloads,
    this.features = const [],
  });

  factory AppPlan.fromJson(Map<String, dynamic> j) => AppPlan(
        id: cleanStr(j['id']) ?? 'free',
        name: cleanStr(j['name']) ?? 'Free',
        price: (j['price'] as num?)?.toDouble(),
        label: cleanStr(j['label']),
        isActive: j['is_active'] == true,
        expiresAt: cleanStr(j['expires_at']),
        durationDays: j['duration_days'] is int ? j['duration_days'] : int.tryParse('${j['duration_days'] ?? ''}'),
        maxProfiles: j['max_profiles'] is int ? j['max_profiles'] : int.tryParse('${j['max_profiles'] ?? ''}'),
        maxDownloads: j['max_downloads'] is int ? j['max_downloads'] : null,
        features: ((j['features']) as List?)?.map((e) => cleanStr(e)).whereType<String>().toList() ?? [],
      );

  static AppPlan free() => AppPlan(id: 'free', name: 'Free', maxProfiles: 1, maxDownloads: 0);
}

class Profile {
  final String id;
  final String? name;
  final bool isKid;
  Profile({required this.id, this.name, this.isKid = false});
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: cleanStr(j['id']) ?? '',
        name: cleanStr(j['name']),
        isKid: j['is_kid'] == true || j['isKid'] == true,
      );
}

class ContentItem {
  final String id;
  final String title;
  final String? poster;
  final String? description;
  final int? year;
  final String? type;
  final double? rating;
  final List<String> genres;
  final double? progress;

  ContentItem({
    required this.id,
    required this.title,
    this.poster,
    this.description,
    this.year,
    this.type,
    this.rating,
    this.genres = const [],
    this.progress,
  });

  factory ContentItem.fromJson(Map<String, dynamic> j) {
    final metaRaw = j['meta'];
    final meta = metaRaw is Map<String, dynamic> ? metaRaw : null;
    // O backend nem sempre usa "title" — em vários endpoints (ex: canais)
    // o campo chama-se "name". Tenta ambos, aninhado e direto.
    final title = cleanStr(meta?['title']) ??
        cleanStr(j['title']) ??
        cleanStr(meta?['name']) ??
        cleanStr(j['name']) ??
        '—';
    return ContentItem(
      id: cleanStr(j['id']) ?? '',
      title: title,
      poster: cleanStr(meta?['poster']) ?? cleanStr(j['poster']),
      description: cleanStr(meta?['description']) ?? cleanStr(j['description']),
      year: j['year'] is int ? j['year'] as int : int.tryParse(cleanStr(j['year']) ?? ''),
      type: cleanStr(j['type']),
      rating: (meta?['rating'] as num?)?.toDouble() ?? (j['rating'] as num?)?.toDouble(),
      genres: ((meta?['genres'] ?? j['genres']) as List?)
              ?.map((e) => cleanStr(e))
              .whereType<String>()
              .toList() ??
          [],
      progress: (j['progress'] as num?)?.toDouble(),
    );
  }
}

class ChannelItem {
  final String id;
  final String name;
  final String? logo;
  final String? group;
  final String? country;
  final String? language;
  final String? url;
  final bool hasAccess;
  final bool locked;

  ChannelItem({
    required this.id,
    required this.name,
    this.logo,
    this.group,
    this.country,
    this.language,
    this.url,
    this.hasAccess = false,
    this.locked = true,
  });

  factory ChannelItem.fromJson(Map<String, dynamic> j) => ChannelItem(
        id: cleanStr(j['id']) ?? '',
        name: cleanStr(j['name']) ?? '',
        logo: cleanStr(j['logo']),
        group: cleanStr(j['group']),
        country: cleanStr(j['country']),
        language: cleanStr(j['language']),
        url: cleanStr(j['url']),
        hasAccess: j['has_access'] == true,
        locked: j['locked'] == true,
      );
}

class DownloadItem {
  final String contentId;
  final String title;
  final String? poster;
  final String quality;
  final DateTime expiresAt;
  final String? localPath;

  DownloadItem({
    required this.contentId,
    required this.title,
    this.poster,
    required this.quality,
    required this.expiresAt,
    this.localPath,
  });
}
