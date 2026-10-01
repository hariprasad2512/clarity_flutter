import 'package:flutter/material.dart';

/// Clarity brand mark (green circle + white check).
///
/// Source: `assets/logo/clarity_mark.png`, generated from
/// `tool/generate_logo_assets.py` to match the uploaded logo.
/// Tray/menu-bar icons intentionally stay monochrome (OS requirement).
class ClarityMark extends StatelessWidget {
  const ClarityMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/clarity_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Graceful fallback if the asset is missing (e.g. stale build):
      // keep the previous generic check so the UI never breaks.
      errorBuilder: (_, _, _) => Icon(
        Icons.check_circle,
        size: size,
        color: Colors.green,
      ),
    );
  }
}
