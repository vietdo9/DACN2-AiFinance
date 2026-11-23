import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Uses the approved wallet artwork on web while preserving the native glyph.
class FinWiseBrandMark extends StatelessWidget {
  const FinWiseBrandMark({
    super.key,
    required this.size,
    required this.fallbackIcon,
    this.fallbackIconSize,
  });

  final double size;
  final IconData fallbackIcon;
  final double? fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.asset(
        'assets/images/finwise_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'FinWise',
      );
    }
    return Icon(fallbackIcon, color: const Color(0xFF4F46E5), size: fallbackIconSize ?? size);
  }
}
