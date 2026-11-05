import 'package:flutter/material.dart';

/// The app logo: a corner of a board with a black and a white stone.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/logo.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
  );
}
