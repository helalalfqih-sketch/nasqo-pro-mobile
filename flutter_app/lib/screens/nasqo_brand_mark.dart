import 'package:flutter/material.dart';

/// Static visual mark from the user's published NASQO web app.
class NasqoBrandMark extends StatelessWidget {
  const NasqoBrandMark({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .19),
        child: Image.asset(
          'assets/nasqo_logo.png',
          width: size,
          height: size,
          cacheWidth: (size * 3).round(),
          fit: BoxFit.contain,
          semanticLabel: 'شعار نسقو برو',
        ),
      );
}
