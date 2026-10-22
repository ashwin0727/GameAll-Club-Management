import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/smooth_switcher.dart';
import '../../../shared/widgets/states.dart';

/// A page under Profile: back arrow, title, a refreshable scrolling body.
class HubPage extends StatelessWidget {
  const HubPage({super.key, required this.title, required this.children, this.onRefresh, this.actions});

  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: children,
    );
    return Scaffold(
      backgroundColor: context.tokens.surface0,
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), actions: actions),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
          ),
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue]-like future: skeleton while loading, a retry on error, the data otherwise.
class HubAsync<T> extends StatelessWidget {
  const HubAsync({super.key, required this.value, required this.onRetry, required this.builder, this.skeletonHeight = 140});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final double skeletonHeight;

  @override
  Widget build(BuildContext context) {
    return SmoothSwitcher(
      child: value.when(
      loading: () => KeyedSubtree(key: const ValueKey('loading'), child: AppSkeleton(height: skeletonHeight, radius: AppRadius.lg)),
      error: (e, _) => Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: ErrorView(message: e is AppException ? e.message : 'Something went wrong. Please try again.', onRetry: onRetry),
      ),
      data: (d) => KeyedSubtree(key: const ValueKey('data'), child: builder(d)),
      ),
    );
  }
}

/// A bordered card with an optional title row — the container every section on these pages uses.
class HubCard extends StatelessWidget {
  const HubCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding});

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.textPrimary)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: TextStyle(fontSize: 12, color: t.textSecondary, height: 1.35)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// A small text-style action (Edit, Manage…) sitting in a card header.
class HubAction extends StatelessWidget {
  const HubAction({super.key, required this.label, required this.onTap, this.icon = Icons.edit_outlined});

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: t.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: t.primary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// A label above its value; a missing value reads "Not added".
class HubInfoRow extends StatelessWidget {
  const HubInfoRow(this.label, this.value, {super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final has = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary)),
          const SizedBox(height: 2),
          Text(
            has ? value! : 'Not added',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: has ? FontWeight.w600 : FontWeight.w400,
              color: has ? t.textPrimary : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted square badge holding an icon.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 44, this.round = false});

  final IconData icon;
  final Color? color;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.tokens.electricBlue;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(round ? size : AppRadius.md),
      ),
      child: Icon(icon, size: size * 0.5, color: c),
    );
  }
}

/// "₹2,999" from minor units.
String hubMoney(int minor) {
  final v = minor / 100;
  final whole = v == v.roundToDouble();
  final text = v.toStringAsFixed(whole ? 0 : 2);
  final parts = text.split('.');
  final digits = parts.first;
  // Indian grouping: last three digits, then pairs.
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    grouped = '${head.replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},')},$tail';
  }
  return '₹$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "31 Dec 2026".
String hubDate(DateTime? d) => d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';
