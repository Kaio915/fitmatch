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
    this.assetPath = 'assets/images/fitmatch_logo.png',
  });

  @override
  Widget build(BuildContext context) {
    final frameHeight = height * zoom;
    final frameWidth = frameHeight * widthFactor;
    final highContrast = onDarkBackground;

    Widget zoomed(Widget child) {
      return ClipRect(
        child: SizedBox(
          height: frameHeight,
          width: frameWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ),
      );
    }

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
      final commonFit = BoxFit.cover;
      final commonAlignment = Alignment.centerLeft;

      if (useNetwork) {
        return Image.network(
          '/assets/$assetPath',
          height: frameHeight,
          width: frameWidth,
          fit: commonFit,
          alignment: commonAlignment,
          color: highContrast ? Colors.white : null,
          colorBlendMode: highContrast ? BlendMode.srcIn : null,
          errorBuilder: (_, __, ___) => textFallback(),
        );
      }

      return Image.asset(
        assetPath,
        height: frameHeight,
        width: frameWidth,
        fit: commonFit,
        alignment: commonAlignment,
        color: highContrast ? Colors.white : null,
        colorBlendMode: highContrast ? BlendMode.srcIn : null,
        errorBuilder: (_, __, ___) {
          if (kIsWeb) {
            return logoRaster(useNetwork: true);
          }
          return textFallback();
        },
      );
    }

    final logo = zoomed(
      logoRaster(useNetwork: false),
    );

    return logo;
  }
}
