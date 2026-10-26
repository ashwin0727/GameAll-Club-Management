import 'package:flutter/material.dart';

import '../../core/access/access.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

const _extraLabels = <String, String>{
  'BOOKINGS_VIEW_CUSTOMER':
      'Can see customer / member contact details on bookings',
  'FINANCE_REOPEN_CLOSING': 'Can reopen a closed day',
  'USERS_MANAGE_FACILITY_ACCESS': 'Can grant access to other facilities',
};

/// The role editor's permission screen: every page of the app, grouped like the menu, each set to None / View / Edit.
/// [selected] is the role's permission-key set (the source of truth); choosing a level rewrites that page's keys.
/// [canGrant] says whether the signed-in editor may hand out a key (an administrator can only grant what they hold).
class PageAccessMatrix extends StatelessWidget {
  const PageAccessMatrix({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.canGrant,
    this.pageInPlan,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool Function(String key) canGrant;

  /// Whether the club's plan includes a page. A page outside the plan cannot be switched on for anyone.
  final bool Function(String pageKey)? pageInPlan;

  bool _inPlan(AccessPage page) => pageInPlan?.call(page.key) ?? true;

  bool _allowed(AccessPage page, AccessLevel level) {
    if (level == AccessLevel.none) return true;
    if (!_inPlan(page)) return false;
    final keys = level == AccessLevel.edit
        ? [...page.viewKeys, ...page.editKeys]
        : page.viewKeys;
    return keys.every(canGrant);
  }

  void _setLevel(AccessPage page, AccessLevel level) =>
      onChanged(withPageLevel(selected, page, level));

  void _setGroup(List<AccessPage> pages, AccessLevel level) {
    var next = {...selected};
    for (final page in pages) {
      if (_allowed(page, level)) next = withPageLevel(next, page, level);
    }
    onChanged(next);
  }

  void _toggle(String key) {
    final next = {...selected};
    if (!next.remove(key)) next.add(key);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unmanaged = selected
        .where((k) => !managedAccessKeys.contains(k))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: t.borderColor),
          ),
          child: Text.rich(
            TextSpan(
              style: AppTypography.caption(context),
              children: const [
                TextSpan(
                  text: 'None',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' — the page is hidden completely. '),
                TextSpan(
                  text: 'View',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' — can look, but not change or export anything. ',
                ),
                TextSpan(
                  text: 'Edit',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' — can also create, change, cancel, record payments and export.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final group in accessGroups) ...[
          _GroupCard(
            label: group.label,
            onAll: (level) => _setGroup(group.pages, level),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < group.pages.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: t.borderColor.withValues(alpha: 0.6),
                    ),
                  _PageRow(
                    page: group.pages[i],
                    level: editorLevelFor(group.pages[i], selected),
                    selected: selected,
                    inPlan: _inPlan(group.pages[i]),
                    allowed: (l) => _allowed(group.pages[i], l),
                    onLevel: (l) => _setLevel(group.pages[i], l),
                    canGrant: canGrant,
                    onToggle: _toggle,
                  ),
                ],
                if (group.label == 'Coaching') ...[
                  Divider(
                    height: 1,
                    color: t.borderColor.withValues(alpha: 0.6),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Limit to their own coach profile',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'For coach roles: Coaching shows only this person\'s own coach profile, sessions, programs and '
                                'students, and the Sessions coach filter is locked to them. Leave Schedule and Reports at None.',
                                style: AppTypography.caption(context),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: selected.contains(coachingOwnOnly),
                          onChanged: canGrant(coachingOwnOnly)
                              ? (_) => _toggle(coachingOwnOnly)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (unmanaged > 0)
          Text(
            '$unmanaged other permission${unmanaged == 1 ? '' : 's'} on this role (for features not shown here) are kept as they are.',
            style: AppTypography.caption(context),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.label,
    required this.onAll,
    required this.child,
  });

  final String label;
  final ValueChanged<AccessLevel> onAll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      // A transparent Material so the check-box rows (ListTiles) paint their ink inside the decorated card.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: t.surface2,
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  PopupMenuButton<AccessLevel>(
                    tooltip: 'Set every page in $label',
                    onSelected: onAll,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: AccessLevel.none,
                        child: Text('All None'),
                      ),
                      PopupMenuItem(
                        value: AccessLevel.view,
                        child: Text('All View'),
                      ),
                      PopupMenuItem(
                        value: AccessLevel.edit,
                        child: Text('All Edit'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Set all',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: t.primary,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down_rounded, color: t.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.page,
    required this.level,
    required this.selected,
    required this.allowed,
    required this.inPlan,
    required this.onLevel,
    required this.canGrant,
    required this.onToggle,
  });

  final AccessPage page;
  final EditorLevel level;
  final Set<String> selected;
  final bool Function(AccessLevel) allowed;
  final bool inPlan;
  final ValueChanged<AccessLevel> onLevel;
  final bool Function(String) canGrant;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final current = switch (level) {
      EditorLevel.none => AccessLevel.none,
      EditorLevel.view => AccessLevel.view,
      EditorLevel.edit => AccessLevel.edit,
      EditorLevel.custom => null,
    };
    final title = page.key == accessPageHome
        ? 'Today (Home on web)'
        : page.label;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(page.description, style: AppTypography.caption(context)),
          if (!inPlan)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Not in your plan — upgrade to Advanced to use this page.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.primary)),
            ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AccessLevel>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              segments: [
                ButtonSegment(
                  value: AccessLevel.none,
                  label: const Text('None'),
                  icon: const Icon(Icons.lock_outline, size: 16),
                ),
                ButtonSegment(
                  value: AccessLevel.view,
                  label: const Text('View'),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  enabled: allowed(AccessLevel.view),
                ),
                if (page.canEdit)
                  ButtonSegment(
                    value: AccessLevel.edit,
                    label: Text(
                      page.editLabel == null ? 'Edit' : 'Edit + export',
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    enabled: allowed(AccessLevel.edit),
                  ),
              ],
              selected: current == null ? const {} : {current},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) onLevel(s.first);
              },
            ),
          ),
          if (level == EditorLevel.custom) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Some, but not all, Edit rights are set here (from before this screen existed). Pick Edit to grant all of them, or View to remove them.',
              style: TextStyle(fontSize: 12, color: t.warning),
            ),
          ],
          if (level != EditorLevel.none)
            for (final key in page.extraKeys)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(key),
                onChanged: canGrant(key) ? (_) => onToggle(key) : null,
                title: Text(
                  _extraLabels[key] ?? key,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
        ],
      ),
    );
  }
}
