import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme.dart';
import '../providers/locale_provider.dart';

const _languages = [
  {'code': 'pt', 'flag': '🇧🇷', 'native': 'Português', 'label': 'Português'},
  {'code': 'en', 'flag': '🇺🇸', 'native': 'English', 'label': 'English'},
  {'code': 'es', 'flag': '🇪🇸', 'native': 'Español', 'label': 'Español'},
];

class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String _selected = 'pt';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset('assets/icons/logo.svg', height: 64),
                  const SizedBox(height: 22),
                  const Text(
                    'Escolha o seu idioma',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textTitle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pode ser alterado nas configurações a qualquer momento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ..._languages.map((lang) {
                    final selected = _selected == lang['code'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _selected = lang['code']!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.cardBg,
                            border: Border.all(
                              color: selected ? AppColors.primary : AppColors.border,
                              width: selected ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Text(lang['flag']!, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(lang['native']!,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                    Text(lang['label']!,
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (selected)
                                const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              // Só grava o idioma — o router reage sozinho
                              // (via refreshListenable) e navega para o
                              // sítio certo. Nenhuma chamada a context.go()
                              // aqui: era essa dupla navegação que causava
                              // o "aparece e desaparece".
                              await ref.read(localeProvider.notifier).setLocale(_selected);
                            },
                      child: _saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
