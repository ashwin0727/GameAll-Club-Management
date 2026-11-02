import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/hover_scope.dart';
import '../../../../core/widgets/pressable.dart';

/// One of the three navigation shortcuts under the carousel.
class PlayerShortcutCard extends StatelessWidget {
  const PlayerShortcutCard({
    super.key,
    required this.title,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.subtitle,
    this.description,
    this.wide = false,
    this.height = AppDimensions.shortcutHeight,
  });

  final String title;
  final String? subtitle;

  /// One sentence under the title (shown in the wide layout only).
  final String? description;

  /// The desktop layout: icon on the left, title and description beside it, arrow on the right.
  final bool wide;
  final IconData icon;

  /// A subtle blue or violet wash over the dark surface.
  final Color tint;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(AppDimensions.cardRadius);
    return Semantics(
      button: true,
      label: title,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: BoxConstraints(minHeight: wide ? 104 : height),
            padding: EdgeInsets.all(wide ? 20 : 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Color.lerp(p.border, tint, 0.35)!),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    tint.withValues(alpha: p.isDark ? 0.18 : 0.10),
                    p.surface,
                  ),
                  p.surface,
                ],
              ),
            ),
            child: wide
                ? _wideContent(p)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 30, color: tint),
                      const SizedBox(height: 10),
                      // Each line stays whole: if the longest word does not fit the card, the text shrinks a little instead of breaking.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: HoverText(
                          title,
                          style: AppTextStyles.shortcutHeading(p.primaryText)
                              .copyWith(fontSize: 13.5),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppTextStyles.meta(p.secondaryText),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.elevated,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: p.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

extension on PlayerShortcutCard {
  Widget _wideContent(AppPalette p) => Row(
    children: [
      Icon(icon, size: 34, color: tint),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HoverText(
              title.replaceAll('\n', ' '),
              style: AppTextStyles.cardHeading(p.primaryText)
                  .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(description!, style: AppTextStyles.support(p.secondaryText)),
            ],
          ],
        ),
      ),
      const SizedBox(width: 12),
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.elevated),
        child: Icon(
          Icons.arrow_forward_rounded,
          size: 18,
          color: p.primaryText,
        ),
      ),
    ],
  );
}

/// The three shortcuts, built from what the player is actually enrolled in:
/// membership -> "My Membership" once active; coaching -> "My Coaching" once enrolled; guest booking is always there.
class PlayerShortcutCards extends StatelessWidget {
  const PlayerShortcutCards({
    super.key,
    required this.hasActiveMembership,
    required this.hasActiveCoaching,
    required this.onNavigate,
    this.wide = false,
  });

  final bool hasActiveMembership;
  final bool hasActiveCoaching;
  final RouteCallback onNavigate;

  /// The desktop layout (see [PlayerShortcutCard.wide]).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PlayerShortcutCard(
        key: const ValueKey('shortcut-membership'),
        wide: wide,
        description: hasActiveMembership
            ? 'View your plan, renewals and sessions.'
            : 'Play regularly. Save more with club memberships.',
        title: hasActiveMembership ? 'My\nMembership' : 'Explore\nMemberships',
        icon: hasActiveMembership
            ? Icons.workspace_premium_rounded
            : Icons.diamond_outlined,
        tint: AppColors.blue,
        onTap: () => onNavigate(
          hasActiveMembership ? AppRoutes.myMembership : AppRoutes.memberships,
        ),
      ),
      PlayerShortcutCard(
        key: const ValueKey('shortcut-coaching'),
        wide: wide,
        description: hasActiveCoaching
            ? 'Your programmes and upcoming sessions.'
            : 'Train with certified coaches and improve your game.',
        title: hasActiveCoaching ? 'My\nCoaching' : 'Explore\nCoaching',
        icon: Icons.school_outlined,
        tint: AppColors.violet,
        onTap: () => onNavigate(
          hasActiveCoaching ? AppRoutes.myCoaching : AppRoutes.coaching,
        ),
      ),
      PlayerShortcutCard(
        key: const ValueKey('shortcut-guest'),
        wide: wide,
        description:
            'Find nearby venues, check available slots and book instantly.',
        title: 'Guest\nCourt\nBooking',
        icon: Icons.event_available_outlined,
        tint: AppColors.purple,
        onTap: () => onNavigate(AppRoutes.guestBooking),
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppDimensions.cardSpacing),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}
