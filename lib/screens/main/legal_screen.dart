import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// LegalScreen — porte 1:1 de app/main/legal/page.tsx (pixel real). Não
/// existia NENHUMA versão disto no app — a aba "Legal" nunca tinha sido
/// construída, daí "informações legais não aparecem" (nem a página
/// existia). 10 abas, cada uma com N secções numeradas (título+corpo),
/// contagens exatas confirmadas contra o JSON real (391 chaves 'legal.*').
class _LegalTab {
  final String key, prefix, labelKey, titleKey;
  final int count;
  const _LegalTab(this.key, this.prefix, this.count, this.labelKey, this.titleKey);
}

const _tabs = [
  _LegalTab('notice', 'notice', 7, 'legal.tabNotice', 'legal.noticeT'),
  _LegalTab('upload', 'upload', 12, 'legal.tabUpload', 'legal.uploadT'),
  _LegalTab('tos', 'tos', 32, 'legal.tabTos', 'legal.tosT'),
  _LegalTab('privacy', 'priv', 19, 'legal.tabPrivacy', 'legal.privacyT'),
  _LegalTab('cookies', 'cookies', 17, 'legal.tabCookies', 'legal.cookiesT'),
  _LegalTab('security', 'sec', 16, 'legal.tabSecurity', 'legal.securityT'),
  _LegalTab('contact', 'contact', 6, 'legal.tabContact', 'legal.contactT'),
  _LegalTab('ipr', 'ipr', 22, 'legal.tabIpr', 'legal.iprT'),
  _LegalTab('dmca', 'dmca', 28, 'legal.tabDmca', 'legal.dmcaT'),
  _LegalTab('counter', 'counter', 26, 'legal.tabCounter', 'legal.counterT'),
];

final _emailRe = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key});
  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  String _tabKey = 'tos'; // mesmo default do site real

  @override
  Widget build(BuildContext context) {
    final active = _tabs.firstWhere((t) => t.key == _tabKey);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('legal.title'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (c, i) {
                final tab = _tabs[i];
                final selected = tab.key == _tabKey;
                return ChoiceChip(
                  label: Text(context.t(tab.labelKey)),
                  selected: selected,
                  onSelected: (_) => setState(() => _tabKey = tab.key),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.cardBg,
                  labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w700),
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t(active.titleKey), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                for (var n = 1; n <= active.count; n++) _section(context, '${active.prefix}${n}t', '${active.prefix}$n'),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String titleKey, String bodyKey) {
    final body = context.t('legal.$bodyKey');
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('legal.$titleKey'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _bodyWithEmails(body),
        ],
      ),
    );
  }

  /// Destaca endereços de e-mail no corpo com link mailto:, igual ao
  /// BodyText do site real — sem parser de markdown, texto simples.
  Widget _bodyWithEmails(String text) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _emailRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final email = m.group(0)!;
      spans.add(TextSpan(
        text: email,
        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: AppColors.primary),
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse('mailto:$email')),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.6),
        children: spans,
      ),
    );
  }
}
