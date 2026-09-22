import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/api_client.dart';

/// PixelChatbot — equivalente a components/PixelChatbot.tsx (botão
/// flutuante "Pixel", visível em todas as páginas de /main via o
/// MainShell, tal como no AppShell.tsx original). Mesmo contrato de rede
/// (ContactApi/ChatApi → POST {UPLOAD}/chat {message, history}, resposta
/// res.reply) e o mesmo comportamento de saudação: aparece uma vez por
/// dispositivo, 5s depois de carregar, esconde sozinha ao fim de 16s ou ao
/// ser tocada — persistido em 'pixgo_pixel_greeted' (SharedPreferences,
/// equivalente ao localStorage do site).
class Message {
  final String role; // 'user' | 'assistant'
  final String content;
  Message(this.role, this.content);
}

class PixelChatbot extends StatefulWidget {
  const PixelChatbot({super.key});
  @override
  State<PixelChatbot> createState() => _PixelChatbotState();
}

class _PixelChatbotState extends State<PixelChatbot> {
  static const _greetingKey = 'pixgo_pixel_greeted';
  static const _greetingDelay = Duration(milliseconds: 5000);
  static const _greetingAutoHide = Duration(milliseconds: 16000);

  bool _open = false;
  bool _showGreeting = false;
  bool _sending = false;
  final _messages = <Message>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _maybeShowGreeting();
  }

  Future<void> _maybeShowGreeting() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_greetingKey) == true) return;
    await Future.delayed(_greetingDelay);
    if (!mounted) return;
    setState(() => _showGreeting = true);
    Future.delayed(_greetingAutoHide, () {
      if (mounted && _showGreeting) _dismissGreeting();
    });
  }

  Future<void> _dismissGreeting() async {
    setState(() => _showGreeting = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_greetingKey, true);
  }

  void _toggle() {
    if (_showGreeting) _dismissGreeting();
    setState(() => _open = !_open);
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final history = _messages
        .skip(_messages.length > 6 ? _messages.length - 6 : 0)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    setState(() {
      _messages.add(Message('user', text));
      _inputController.clear();
      _sending = true;
    });
    _scrollToEnd();
    try {
      final reply = await chatApi.send(text, history);
      setState(() => _messages.add(Message('assistant', reply ?? context.t('chatbot.error'))));
    } catch (_) {
      setState(() => _messages.add(Message('assistant', context.t('chatbot.error'))));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_showGreeting && !_open)
          Positioned(
            right: 8,
            bottom: 78,
            child: GestureDetector(
              onTap: _toggle,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 230),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 30, offset: const Offset(0, 8))],
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.t('chatbot.greeting'), style: const TextStyle(fontSize: 12.5, height: 1.4))),
                ]),
              ),
            ),
          ),
        if (_open)
          Positioned(
            right: 8,
            bottom: 78,
            child: _ChatPanel(
              messages: _messages,
              sending: _sending,
              inputController: _inputController,
              scrollController: _scrollController,
              onSend: _send,
              onClose: _toggle,
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton(
            heroTag: 'pixel_chatbot_fab',
            backgroundColor: AppColors.primary,
            onPressed: _toggle,
            child: Icon(_open ? Icons.close : Icons.chat_bubble_outline, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _ChatPanel extends StatelessWidget {
  final List<Message> messages;
  final bool sending;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const _ChatPanel({
    required this.messages,
    required this.sending,
    required this.inputController,
    required this.scrollController,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        height: 420,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40, offset: const Offset(0, 12))],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              const Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(context.t('chatbot.name'), style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(context.t('chatbot.subtitle'), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(12),
              children: [
                if (messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _bubble(context.t('chatbot.welcome'), isUser: false),
                  ),
                ...messages.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _bubble(m.content, isUser: m.role == 'user'),
                    )),
                if (sending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.t('chatbot.placeholder'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.send, size: 18, color: AppColors.primary), onPressed: onSend),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(String text, {required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary.withOpacity(0.16) : AppColors.cardHover,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
      ),
    );
  }
}
