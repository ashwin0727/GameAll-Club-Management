import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pressable.dart';

/// Whether the page is on a wide window (the web): the profile pages then use the full width with two columns.
bool profileIsWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

/// A page opened from My Profile: the app bar with the title next to the back arrow. On a phone it is one column; on a wide window
/// it uses the page width (the same side margins as the rest of the web layout), so there are no empty bands at the sides.
class ProfileSubPage extends StatelessWidget {
  const ProfileSubPage({
    super.key,
    required this.title,
    required this.child,
    this.scroll = true,
  });

  final String title;
  final Widget child;

  /// False when the child scrolls by itself (a list).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = profileIsWide(context);
    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    final body = scroll
        ? SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(side, wide ? 12 : 8, side, 40),
            child: child,
          )
        : Padding(padding: EdgeInsets.symmetric(horizontal: side), child: child);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(title, style: AppTextStyles.cardHeading(p.primaryText)),
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Two columns on a wide window ([left] and [right] side by side, in the proportion [leftFlex] : [rightFlex]); one column on a phone.
class ProfileColumns extends StatelessWidget {
  const ProfileColumns({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
    this.gap = 24,
  });

  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!profileIsWide(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        SizedBox(width: gap),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }
}

/// A rounded panel, the same on every profile page.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: p.surface,
        border: Border.all(color: p.isDark ? const Color(0xFF2E3B63) : p.border),
      ),
      child: child,
    );
  }
}

/// A small heading above a group of rows.
class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      text,
      style: AppTextStyles.cardHeading(context.palette.primaryText),
    ),
  );
}

/// An icon tile, a title with a line under it, and a chevron: one row of a menu.
class ProfileMenuRow extends StatelessWidget {
  const ProfileMenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Replaces the chevron (a switch, a value).
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tint = danger ? AppColors.danger : p.highlight;
    return Semantics(
      button: onTap != null,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: tint.withValues(alpha: p.isDark ? 0.14 : 0.10),
                    border: Border.all(color: tint.withValues(alpha: 0.28)),
                  ),
                  child: Icon(icon, size: 22, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardHeading(
                          danger ? AppColors.danger : p.primaryText,
                        ).copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.support(p.secondaryText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 26,
                      color: p.secondaryText,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline between menu rows.
class ProfileDivider extends StatelessWidget {
  const ProfileDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.palette.border);
}

/// A quiet one-line message under a heading ("Nothing here yet").
class ProfileEmpty extends StatelessWidget {
  const ProfileEmpty(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 40, color: p.mutedText),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.body(p.secondaryText),
          ),
        ],
      ),
    );
  }
}
