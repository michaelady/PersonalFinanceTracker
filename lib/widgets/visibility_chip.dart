import 'package:flutter/material.dart';

import '../domain/models/models.dart';
import '../theme/zentho_colors.dart';

class VisibilityChip extends StatelessWidget {
  const VisibilityChip(this.visibility, {super.key});

  final VisibilityScope visibility;

  @override
  Widget build(BuildContext context) {
    final isShared = visibility == VisibilityScope.shared;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isShared ? ZenthoColors.shared : ZenthoColors.private)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isShared ? 'Shared' : 'Private',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isShared ? ZenthoColors.shared : ZenthoColors.private,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
