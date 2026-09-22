import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme.dart';

/// SplashScreen — apenas visual. TODA a navegação (idioma → login/main)
/// é decidida centralmente pelo redirect do router (ver core/router.dart).
/// Este ecrã NUNCA chama context.go() — isso foi a causa da corrida que
/// fazia o ecrã de idioma aparecer e desaparecer.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset('assets/icons/logo.svg', height: 72),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}
