import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FitMatchLogo extends StatelessWidget {
  final double height;
  final double zoom;
  final double widthFactor;
  final bool onDarkBackground;
  final String assetPath;

  const FitMatchLogo({
    super.key,
    this.height = 34,
    this.zoom = 1.0,
    this.widthFactor = 3.8,
    this.onDarkBackground = false,
    this.assetPath = 'assets/images/fitmatch_logo3.png',
  });

  @override
  Widget build(BuildContext context) {
    final frameHeight = height * zoom;
    final frameWidth = frameHeight * widthFactor;

    Widget textFallback() {
      return Text(
        'FitMatch',
        style: TextStyle(
          color: onDarkBackground ? Colors.white : const Color(0xFF0B4DBA),
          fontSize: frameHeight * 0.46,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      );
    }

    Widget logoRaster({required bool useNetwork}) {
      final commonFit = BoxFit.contain;
      final commonAlignment = Alignment.centerLeft;

      if (useNetwork) {
        return Image.network(
          '/assets/$assetPath',
          height: frameHeight,
          fit: commonFit,
          alignment: commonAlignment,
          errorBuilder: (_, __, ___) => textFallback(),
        );
      }

      return Image.asset(
        assetPath,
        height: frameHeight,
        fit: commonFit,
        alignment: commonAlignment,
        errorBuilder: (_, __, ___) {
          if (kIsWeb) {
            return logoRaster(useNetwork: true);
          }
          return textFallback();
        },
      );
    }

    final logo = logoRaster(useNetwork: false);

    if (onDarkBackground) {
      // Força RGB → branco, preserva o alpha original do PNG transparente
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0, 0, 0, 0, 255, // R = 255
          0, 0, 0, 0, 255, // G = 255
          0, 0, 0, 0, 255, // B = 255
          0, 0, 0, 1, 0,   // A = alpha original (preservado)
        ]),
        child: logo,
      );
    }

    return logo;
  }
}
