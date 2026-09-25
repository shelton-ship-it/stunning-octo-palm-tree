import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_client.dart';

/// TvPairingDialog — gera o código de 6 dígitos (POST /auth/device/code,
/// api-core) para parear a TV. Backend já existia por completo
/// (routes/device.js) — só não havia nenhum botão/ecrã na app para o
/// disparar. Sem chaves de i18n reais para isto em nenhuma das telas
/// existentes (nem no site) — texto literal em PT, igual ao já usado nos
/// ecrãs sem i18n oficial (ex: checkout ZumboPay).
class TvPairingDialog extends StatefulWidget {
  const TvPairingDialog({super.key});
  @override
  State<TvPairingDialog> createState() => _TvPairingDialogState();
}

class _TvPairingDialogState extends State<TvPairingDialog> {
  bool _loading = true;
  String? _error;
  String? _code;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    _timer?.cancel();
    try {
      final data = await deviceApi.code();
      final code = data['code']?.toString() ?? '';
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 300;
      setState(() { _code = code; _secondsLeft = expiresIn; _loading = false; });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_secondsLeft <= 1) {
          t.cancel();
          setState(() => _secondsLeft = 0);
        } else {
          setState(() => _secondsLeft--);
        }
      });
    } on ApiException catch (e) {
      setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      setState(() { _loading = false; _error = 'Não foi possível gerar o código agora.'; });
    }
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: const Text('Parear com a TV'),
      content: SizedBox(
        width: 280,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Abra o PixGo na sua TV e digite o código abaixo para entrar com a sua conta.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppColors.primary))
          else if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.primary, fontSize: 13)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _generate, child: const Text('Tentar novamente')),
          ] else ...[
            Text(
              _code!.replaceAllMapped(RegExp(r'.{1,3}'), (m) => '${m.group(0)} ').trim(),
              style: const TextStyle(fontFamily: AppTheme.fontDisplay, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4),
            ),
            const SizedBox(height: 10),
            Text(
              _secondsLeft > 0 ? 'Expira em ${_fmt(_secondsLeft)}' : 'Código expirado',
              style: TextStyle(fontSize: 12, color: _secondsLeft > 0 ? AppColors.textMuted : AppColors.primary),
            ),
            if (_secondsLeft == 0) ...[
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _generate, child: const Text('Gerar novo código')),
            ],
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
