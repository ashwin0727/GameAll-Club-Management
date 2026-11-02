import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/pressable.dart';

/// The five main destinations. The centre one (Quick) is an action, not a page.
enum PlayerTab { home, bookings, quick, explore, profile }

const _labels = {
  PlayerTab.home: 'Home',
  PlayerTab.bookings: 'Bookings',
  PlayerTab.quick: 'Quick',
  PlayerTab.explore: 'Explore',
  PlayerTab.profile: 'Profile',
};

const _icons = {
  PlayerTab.home: Icons.home_rounded,
  PlayerTab.bookings: Icons.calendar_month_outlined,
  PlayerTab.explore: Icons.explore_outlined,
  PlayerTab.profile: Icons.person_outline_rounded,
};

class PlayerBottomNavigation extends StatelessWidget {
  const PlayerBottomNavigation({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onQuick,
  });

  final PlayerTab current;
  final ValueChanged<PlayerTab> onSelect;
  final VoidCallback onQuick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = p.isDark ? p.highlight : p.primary;
    // Taller when the system font is enlarged, so the labels never clip.
    final extra =
        (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 20) * 1.5;
    return Container(
      decoration: BoxDecoration(
        color: p.secondaryBackground,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppDimensions.bottomNavHeight + extra,
          child: Row(
            children: [
              for (final tab in PlayerTab.values)
                Expanded(
                  child: tab == PlayerTab.quick
                      ? _QuickButton(onTap: onQuick)
                      : _NavItem(
                          key: ValueKey('nav-${tab.name}'),
                          label: _labels[tab]!,
                          icon: _icons[tab]!,
                          selected: tab == current,
                          activeColor: active,
                          inactiveColor: p.secondaryText,
                          onTap: () => onSelect(tab),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.1 : 1,
                duration: const Duration(milliseconds: 200),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 4),
              Text(label, style: AppTextStyles.navLabel(color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Quick actions',
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Pressable(
              onTap: onTap,
              scale: 0.92,
              borderRadius: BorderRadius.circular(AppDimensions.quickButton),
              child: Container(
                key: const ValueKey('nav-quick'),
                width: AppDimensions.quickButton,
                height: AppDimensions.quickButton,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.violet.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text('Quick', style: AppTextStyles.navLabel(p.secondaryText)),
          ],
        ),
      ),
    );
  }
}
