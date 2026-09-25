import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/theme.dart';

/// skeletons.dart — porte de components/ui/Skeleton.tsx: troca o spinner
/// genérico por placeholders com a forma real do conteúdo em /main,
/// /catalog e /channels. Puramente visual, igual ao site.
Widget _shimmerBox({double? width, double? height, BorderRadius? radius}) {
  return Shimmer.fromColors(
    baseColor: AppColors.cardBg,
    highlightColor: AppColors.cardHover,
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: radius ?? BorderRadius.circular(6)),
    ),
  );
}

class ContentCardSkeleton extends StatelessWidget {
  const ContentCardSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _shimmerBox(width: double.infinity, radius: BorderRadius.circular(10))),
      const SizedBox(height: 6),
      _shimmerBox(width: double.infinity, height: 10),
      const SizedBox(height: 4),
      _shimmerBox(width: 40, height: 9),
    ]);
  }
}

class ContentGridSkeleton extends StatelessWidget {
  final int count;
  const ContentGridSkeleton({super.key, this.count = 12});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.52,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: count,
      itemBuilder: (c, i) => const ContentCardSkeleton(),
    );
  }
}

class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(children: [
        Positioned.fill(child: _shimmerBox(radius: BorderRadius.circular(12))),
        Positioned(
          left: 20, right: 20, bottom: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _shimmerBox(width: 90, height: 12),
            const SizedBox(height: 10),
            _shimmerBox(width: 180, height: 26),
            const SizedBox(height: 8),
            _shimmerBox(width: 120, height: 12),
          ]),
        ),
      ]),
    );
  }
}

class ChannelCardSkeleton extends StatelessWidget {
  const ChannelCardSkeleton({super.key});
  @override
  Widget build(BuildContext context) => _shimmerBox(width: double.infinity, height: double.infinity, radius: BorderRadius.circular(10));
}

class ChannelsGridSkeleton extends StatelessWidget {
  final int count;
  const ChannelsGridSkeleton({super.key, this.count = 12});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 1.7, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: count,
      itemBuilder: (c, i) => const ChannelCardSkeleton(),
    );
  }
}
