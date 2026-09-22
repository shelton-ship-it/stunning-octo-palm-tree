import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _curPw = TextEditingController();
  final _newPw = TextEditingController();
  bool _saving = false;

  // Perfis (FIX: em falta — a API já expunha POST/PUT/DELETE /auth/profiles,
  // mas não havia UI nenhuma para os usar no mobile; espelha a aba
  // "Perfis" já existente em account/page.tsx no frontend web.)
  final _profileName = TextEditingController();
  bool _profileIsKid = false;
  String? _editingProfileId;
  bool _profileFormOpen = false;
  bool _profileSaving = false;

  // Ajuda: denúncia de abuso + suporte (mesma estrutura da aba "Ajuda" já
  // existente em account/page.tsx no frontend web)
  final _reportTitle = TextEditingController();
  final _reportReason = TextEditingController();
  bool _reportSending = false;
  final _supportEmail = TextEditingController();
  final _supportMsg = TextEditingController();
  bool _supportSending = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    final u = ref.read(authProvider).user;
    _name.text = u?.name ?? '';
    _email.text = u?.email ?? '';
  }

  @override
  void dispose() {
    _tab.dispose();
    _name.dispose();
    _email.dispose();
    _curPw.dispose();
    _newPw.dispose();
    _profileName.dispose();
    _reportTitle.dispose();
    _reportReason.dispose();
    _supportEmail.dispose();
    _supportMsg.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{};
      if (_name.text.trim().isNotEmpty) body['name'] = _name.text.trim();
      if (_email.text.trim().isNotEmpty) body['email'] = _email.text.trim();
      await authApi.update(body);
      await ref.read(authProvider.notifier).refreshMe();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('account.saved'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('common.error'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPw.text.length < 8) return;
    setState(() => _saving = true);
    try {
      await authApi.changePassword({'current_password': _curPw.text, 'new_password': _newPw.text});
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/auth/login');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha atual incorreta')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openNewProfileForm() {
    setState(() {
      _editingProfileId = null;
      _profileName.text = '';
      _profileIsKid = false;
      _profileFormOpen = true;
    });
  }

  void _openEditProfileForm(Profile p) {
    setState(() {
      _editingProfileId = p.id;
      _profileName.text = p.name ?? '';
      _profileIsKid = p.isKid;
      _profileFormOpen = true;
    });
  }

  void _closeProfileForm() {
    setState(() {
      _profileFormOpen = false;
      _editingProfileId = null;
    });
  }

  Future<void> _saveProfileEntry() async {
    final name = _profileName.text.trim();
    if (name.isEmpty) return;
    setState(() => _profileSaving = true);
    try {
      if (_editingProfileId != null) {
        await profilesApi.update(_editingProfileId!, {'name': name, 'is_kid': _profileIsKid});
      } else {
        await profilesApi.create({'name': name, 'is_kid': _profileIsKid});
      }
      await ref.read(authProvider.notifier).refreshMe();
      if (mounted) _closeProfileForm();
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = (e.message.contains('máximo') || e.status == 403)
          ? '${context.t('account.profiles')}: ${context.t('account.profileLimitReached')}'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('common.error'))));
    } finally {
      if (mounted) setState(() => _profileSaving = false);
    }
  }

  Future<void> _deleteProfileEntry(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.bgDarker,
        content: Text(context.t('account.confirmDeleteProfile')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(context.t('account.deleteProfile'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await profilesApi.delete(id);
      await ref.read(authProvider.notifier).refreshMe();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('common.error'))));
    }
  }

  Future<void> _sendReport() async {
    final title = _reportTitle.text.trim();
    final reason = _reportReason.text.trim();
    if (title.isEmpty || reason.isEmpty) return;
    setState(() => _reportSending = true);
    try {
      await contactApi.reportAbuse(title, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('contact.reportSuccess'))));
        setState(() { _reportTitle.clear(); _reportReason.clear(); });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('common.error'))));
    } finally {
      if (mounted) setState(() => _reportSending = false);
    }
  }

  Future<void> _sendSupport() async {
    final email = _supportEmail.text.trim();
    final msg = _supportMsg.text.trim();
    if (email.isEmpty || msg.isEmpty) return;
    setState(() => _supportSending = true);
    try {
      await contactApi.support(email, msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('contact.supportSuccess'))));
        setState(() { _supportEmail.clear(); _supportMsg.clear(); });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('common.error'))));
    } finally {
      if (mounted) setState(() => _supportSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final plan = auth.plan;
    final profiles = auth.profiles;
    final isPremium = plan != null && plan.id != 'free';
    final initials = (user?.name.isNotEmpty == true ? user!.name : (user?.username ?? '?'))
        .split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
    final maxProfiles = plan?.maxProfiles;
    final atLimit = maxProfiles != null && profiles.length >= maxProfiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('account.title'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: context.t('account.profile')),
            Tab(text: context.t('account.profiles')),
            Tab(text: context.t('account.security')),
            Tab(text: context.t('account.subscription')),
            Tab(text: context.t('contact.support')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              // Perfil (dados da conta)
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 23,
                        backgroundColor: AppColors.primary,
                        child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      const SizedBox(width: 14),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('@${user?.username ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPremium ? AppColors.primary.withOpacity(0.15) : Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(plan?.id ?? 'free', style: const TextStyle(fontSize: 10)),
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Text(context.t('auth.fullName'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(controller: _name),
                  const SizedBox(height: 12),
                  Text('${context.t('auth.email')} (${context.t('auth.emailOptional')})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveProfile,
                    child: _saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.t('account.saveName')),
                  ),
                ]),
              ),

              // Perfis (perfis de utilização — quem assiste, tipo Netflix)
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (maxProfiles != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${profiles.length} de $maxProfiles perfis usados'
                        '${atLimit ? ' — ${context.t('account.profileLimitReached')}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                  ...profiles.map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [AppColors.primary, Color(0xFF8C3BFF)])),
                            child: Text((p.name?.isNotEmpty == true ? p.name![0] : '?').toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(children: [
                              Flexible(child: Text(p.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                              if (p.isKid) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.child_care, size: 15, color: AppColors.textMuted)),
                            ]),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: context.t('account.editProfile'),
                            onPressed: () => _openEditProfileForm(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: profiles.length <= 1 ? context.t('account.lastProfileHint') : context.t('account.deleteProfile'),
                            onPressed: profiles.length <= 1 ? null : () => _deleteProfileEntry(p.id),
                          ),
                        ]),
                      )),
                  const SizedBox(height: 8),
                  if (_profileFormOpen)
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t('auth.fullName'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(controller: _profileName, autofocus: true, onChanged: (_) => setState(() {})),
                        const SizedBox(height: 10),
                        Row(children: [
                          Checkbox(
                            value: _profileIsKid,
                            activeColor: AppColors.primary,
                            onChanged: (v) => setState(() => _profileIsKid = v ?? false),
                          ),
                          Text(context.t('account.kidProfile')),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          ElevatedButton(
                            onPressed: (_profileSaving || _profileName.text.trim().isEmpty) ? null : _saveProfileEntry,
                            child: _profileSaving
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(context.t('account.saveName')),
                          ),
                          const SizedBox(width: 8),
                          TextButton(onPressed: _closeProfileForm, child: Text(context.t('common.cancel'))),
                        ]),
                      ]),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: atLimit ? null : _openNewProfileForm,
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(context.t('account.addProfile')),
                    ),
                ]),
              ),

              // Segurança
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('account.currentPassword'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(controller: _curPw, obscureText: true),
                  const SizedBox(height: 12),
                  Text(context.t('account.newPassword'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(controller: _newPw, obscureText: true),
                  Text(context.t('auth.minPassword'), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: (_saving || _curPw.text.isEmpty || _newPw.text.length < 8) ? null : _changePassword,
                    child: _saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.t('account.changePassword')),
                  ),
                ]),
              ),

              // Assinatura
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isPremium ? AppColors.primary.withOpacity(0.06) : AppColors.bgDarker,
                      border: Border.all(color: isPremium ? AppColors.primary.withOpacity(0.25) : AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${plan?.id ?? 'free'} Plan', style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontWeight: FontWeight.w800)),
                          Text(isPremium ? context.t('account.premiumDesc') : context.t('account.freeDesc'),
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ]),
                      ),
                      if (!isPremium)
                        ElevatedButton(onPressed: () => context.go('/main/plans'), child: Text(context.t('account.upgrade'))),
                    ]),
                  ),
                ]),
              ),

              // Ajuda: denúncia + copyright + suporte + sobre
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Denúncia de conteúdo abusivo/ilícito
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('contact.report'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 10),
                      Text(context.t('contact.reportTitleLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _reportTitle, maxLength: 300),
                      const SizedBox(height: 6),
                      Text(context.t('contact.reportReasonLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _reportReason, maxLines: 3, maxLength: 2000),
                      ElevatedButton(
                        onPressed: _reportSending ? null : _sendReport,
                        child: _reportSending
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(context.t('contact.reportSubmit')),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Direitos autorais — só e-mail
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('contact.copyright'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(context.t('contact.copyrightDesc'), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      SelectableText(context.t('contact.copyrightEmail'),
                          style: const TextStyle(fontFamily: 'monospace', color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Suporte — e-mail + formulário
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('contact.support'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 4),
                      SelectableText(context.t('contact.supportEmail'),
                          style: const TextStyle(fontFamily: 'monospace', color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 10),
                      Text(context.t('contact.supportEmailLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _supportEmail, keyboardType: TextInputType.emailAddress, maxLength: 300),
                      const SizedBox(height: 6),
                      Text(context.t('contact.supportMessageLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(controller: _supportMsg, maxLines: 3, maxLength: 4000),
                      ElevatedButton(
                        onPressed: _supportSending ? null : _sendSupport,
                        child: _supportSending
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(context.t('contact.supportSubmit')),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Sobre
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.bgDarker, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('about.title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 10),
                      ...['p1', 'p2', 'p3', 'p4'].map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(context.t('about.${p}t'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textTitle)),
                              const SizedBox(height: 4),
                              Text(context.t('about.$p'), style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5)),
                            ]),
                          )),
                    ]),
                  ),
                ]),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/auth/login');
          },
          icon: const Icon(Icons.logout, color: AppColors.primary, size: 18),
          label: Text(context.t('nav.signOut'), style: const TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}
