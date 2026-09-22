import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/downloads_service.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  bool _loading = true;
  List<DownloadItem> _downloads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DownloadsService.instance.purgeExpired();
    final items = await DownloadsService.instance.listDownloads();
    setState(() { _downloads = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(authProvider).plan;
    // max_downloads:0 só no free; monthly/quarterly/annual têm cota real
    // (20/200/ilimitado) — a versão anterior excluía 'quarterly' por engano.
    final canDownload = plan != null && plan.id != 'free';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.download_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Downloads', style: TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${_downloads.length} títulos guardados', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ]),
        const SizedBox(height: 14),
        if (!canDownload)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Download disponível nos planos pagos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  const Text('Faça upgrade para descarregar conteúdo offline.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ),
              TextButton(onPressed: () => context.go('/main/plans'), child: const Text('Ver planos')),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _downloads.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.download_outlined, size: 32, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        const Text('Sem downloads'),
                        const SizedBox(height: 4),
                        Text(
                          canDownload
                              ? 'Abra um filme ou série e baixe para assistir offline.'
                              : 'Disponível nos planos pagos.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    )
                  : ListView.separated(
                      itemCount: _downloads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (c, i) {
                        final d = _downloads[i];
                        final daysLeft = d.expiresAt.difference(DateTime.now()).inDays;
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(children: [
                            Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.movie, color: AppColors.textMuted),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text('${d.quality.toUpperCase()} · expira em ${daysLeft}d',
                                    style: TextStyle(fontSize: 11, color: daysLeft <= 3 ? AppColors.primary : AppColors.textMuted)),
                              ]),
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_arrow, color: AppColors.primary),
                              onPressed: () => context.push('/main/watch/${d.contentId}?offline=1'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
                              onPressed: () async {
                                await DownloadsService.instance.deleteDownload(d.contentId);
                                _load();
                              },
                            ),
                          ]),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
