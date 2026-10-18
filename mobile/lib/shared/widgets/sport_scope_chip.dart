import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sports/sport_selection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/sports/sport_scope.dart';

/// The "All Sports" selector for an app bar: shows what is selected and opens a sheet to tick any combination of the
/// facility's sports. Every page that reports on sports follows it. With [locked] (Maintenance, Staff and Inventory
/// look at the whole facility) it just reads "All Sports" and can't be changed.
class SportScopeChip extends ConsumerWidget {
  const SportScopeChip({super.key, this.locked = false});

  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scope = ref.watch(sportScopeProvider);
    if (scope.options.length < 2 && !locked) return const SizedBox.shrink();

    final label = locked ? 'All Sports' : scope.label;
    final child = Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: locked ? tokens.textSecondary : tokens.textPrimary),
            ),
          ),
          if (!locked) ...[
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: tokens.textSecondary),
          ],
        ],
      ),
    );

    return Semantics(
      button: !locked,
      label: 'Sports: $label',
      child: locked
          ? Opacity(opacity: 0.7, child: child)
          : InkWell(borderRadius: BorderRadius.circular(999), onTap: () => _open(context), child: child),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SportSheet(),
    );
  }
}

class _SportSheet extends ConsumerWidget {
  const _SportSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(sportScopeProvider);
    final ids = [for (final o in scope.options) o.id];
    final notifier = ref.read(sportSelectionProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Show data for', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: scope.isAll,
              title: const Text('All Sports', style: TextStyle(fontWeight: FontWeight.w700)),
              onChanged: (_) => notifier.selectAll(),
            ),
            const Divider(height: 1),
            for (final o in scope.options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: scope.selection.ids.contains(o.id),
                title: Text('${o.icon}  ${o.name}'),
                onChanged: (_) => notifier.set(toggleSportSelection(ref.read(sportSelectionProvider), ids, o.id)),
              ),
          ],
        ),
      ),
    );
  }
}
