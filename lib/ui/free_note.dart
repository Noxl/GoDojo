import 'package:flutter/material.dart';

/// What Go Dojo is: free, and not made to earn money.
const kFreeNote =
    'Go Dojo is free and open source, made by a Go player for Go players. '
    'No ads, no subscription, nothing to buy, and your data is never sold: '
    'it is just a place to practise.';

const kSourceUrl = 'github.com/Noxl/GoDojo';

/// [kFreeNote] in small print, with where the source code is.
class FreeNote extends StatelessWidget {
  const FreeNote({super.key, this.center = true});

  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          kFreeNote,
          style: style,
          textAlign: center ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: 4),
        SelectableText('Source code: $kSourceUrl', style: style),
      ],
    );
  }
}
