import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';

class ContentCardWidget extends StatelessWidget {
  final ContentItem item;
  final VoidCallback? onTap;
  final VoidCallback? onAddToList;

  const ContentCardWidget({super.key, required this.item, this.onTap, this.onAddToList});

  @override
  Widget build(BuildContext context) {
    final typeColor = AppColors.forType(item.type);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.poster != null && item.poster!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.poster!,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => _placeholder(),
                          placeholder: (c, u) => Container(color: AppColors.cardBg),
                        )
                      : _placeholder(),
                ),
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(height: 3, color: typeColor),
                ),
                if (onAddToList != null)
                  Positioned(
                    top: 8, left: 8,
                    child: GestureDetector(
                      onTap: onAddToList,
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.68),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                if (item.rating != null && item.rating! > 0)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star, size: 11, color: Color(0xFFFFD700)),
                        const SizedBox(width: 3),
                        Text(item.rating!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                  ),
                if (item.type != null)
                  Positioned(
                    bottom: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(context.t('catalog.${item.type}'),
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                if (item.progress != null && item.progress! > 0)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      height: 3,
                      color: Colors.white.withOpacity(0.15),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (item.progress! / 100).clamp(0, 1),
                        child: Container(color: AppColors.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textTitle),
          ),
          if (item.year != null)
            Text('${item.year}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.cardBg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined, size: 32, color: AppColors.textMuted),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ),
          ],
        ),
      );
}
