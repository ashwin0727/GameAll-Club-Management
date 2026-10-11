import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

// The pieces every "hub" page (Memberships, Coaching) is built from, drawn once so the pages match:
// a pill tab strip under the title, a photo hero card with its headline number, and the violet
// floating create button.

/// The pill-shaped tab strip that sits under a hub page's title.
class HubTabBar extends StatelessWidget implements PreferredSizeWidget {
  const HubTabBar({super.key, required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: tokens.surface0,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: tokens.borderColor),
        ),
        child: TabBar(
          controller: controller,
          indicator: BoxDecoration(
            color: tokens.surface3,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: tokens.borderColor),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          labelColor: tokens.textPrimary,
          unselectedLabelColor: tokens.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [for (final l in labels) Tab(text: l)],
        ),
      ),
    );
  }
}

/// A photo hero card: a title, one big number, and a few small figures beneath it.
class HubHeroCard extends StatelessWidget {
  const HubHeroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.figs,
    this.asset = 'assets/images/members_card.png',
  });

  final IconData icon;
  final String title;
  final String value;
  final List<({String value, String label})> figs;
  final String asset;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFFFFFFF);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo background with dark overlays so the white text stays legible.
            Image.asset(asset, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.15)],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.45)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: white),
                      const SizedBox(width: 6),
                      Text(title, style: TextStyle(fontSize: 13, color: white.withValues(alpha: 0.8))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: white)),
                  const SizedBox(height: 10),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.6,
                    child: Container(height: 1, color: white.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Equal columns that wrap, so longer labels ("upcoming sessions") never overflow.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < figs.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(figs[i].value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: white)),
                              Text(figs[i].label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: white.withValues(alpha: 0.75))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The violet pill action button that floats above the bottom nav.
class HubCreateFab extends StatelessWidget {
  const HubCreateFab({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: tokens.accentSolid(tokens.violet),
          boxShadow: [
            BoxShadow(color: tokens.violet.withValues(alpha: 0.42), blurRadius: 20, spreadRadius: -2, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A collapsible tile in the style of "View More Insights": a header that expands to show [child].
class HubExpandPanel extends StatelessWidget {
  const HubExpandPanel({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.violet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.violet.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: tokens.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
