import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The GameAll lockup — logo + "GameAll" over "Club Management". Dropped into
/// the empty space at the bottom of a scrolling page so no screen ends on a
/// blank gap. Pass [subtitle] to show a line under it (e.g. the facility name).
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.subtitle, this.padding});

  final String? subtitle;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: 0.9,
                child: Image.asset('assets/images/logo-icon.png',
                    width: 24, height: 24),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('GameAll',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: tokens.textSecondary)),
                  Text('Club Management',
                      style: TextStyle(
                          fontSize: 8,
                          height: 1.2,
                          color:
                              tokens.textSecondary.withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    color: tokens.textSecondary.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }
}
