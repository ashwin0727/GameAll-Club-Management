import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/maintenance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'maintenance_court_options.dart';

/// Maintenance → Create Ticket. Mobile uses one grouped, scrollable form
/// (spec §"structured form" alternative to a multi-step wizard) with the
/// same three sections as the web wizard: Issue Details, Schedule,
/// Assignment. Styled to match the app's other "create" screens (numbered
/// bordered sections, `AppDropdown`, a sticky gradient CTA) rather than bare
/// Material defaults.
class CreateMaintenanceTicketScreen extends ConsumerStatefulWidget {
  const CreateMaintenanceTicketScreen({super.key});

  @override
  ConsumerState<CreateMaintenanceTicketScreen> createState() => _CreateMaintenanceTicketScreenState();
}

class _CreateMaintenanceTicketScreenState extends ConsumerState<CreateMaintenanceTicketScreen> {
  bool _loading = true;
  String? _loadError;
  List<MaintenanceCourtOption> _courts = const [];
  List<MaintenanceIssueCategory> _categories = const [];
  List<FacilityStaffOption> _staff = const [];

  String? _courtId;
  String? _categoryId;
  MaintenancePriority _priority = MaintenancePriority.medium;
  final _title = TextEditingController();
  final _description = TextEditingController();

  bool _schedule = false;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime _end = DateTime.now().add(const Duration(hours: 4));
  int _affectedCount = 0;

  String? _assignedTo;
  final _estimatedCost = TextEditingController();
  final _notes = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description]) {
      c.addListener(_onFieldChanged);
    }
    _load();
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimatedCost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    try {
      final courts = await loadMaintenanceCourtOptions(ref, facility.id);
      final cats = await ref.read(maintenanceRepositoryProvider).listIssueCategories(facility.id, includeInactive: false);
      final staff = await ref.read(maintenanceRepositoryProvider).listAssignableStaff(facility.id);
      if (!mounted) return;
      setState(() {
        _courts = courts;
        _categories = cats;
        _staff = staff;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _checkConflicts() async {
    if (!_schedule || _courtId == null || !_end.isAfter(_start)) {
      setState(() => _affectedCount = 0);
      return;
    }
    try {
      final rows = await ref.read(maintenanceRepositoryProvider).detectAffectedBookings(_courtId!, _start, _end);
      if (mounted) setState(() => _affectedCount = rows.length);
    } catch (_) {
      if (mounted) setState(() => _affectedCount = 0);
    }
  }

  bool get _valid =>
      _courtId != null &&
      _categoryId != null &&
      _title.text.trim().length >= 3 &&
      _description.text.trim().length >= 5 &&
      (!_schedule || _end.isAfter(_start));

  Future<void> _submit() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null || !_valid) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final id = await ref.read(maintenanceRepositoryProvider).createTicket(
            facilityId: facility.id,
            courtId: _courtId!,
            issueCategoryId: _categoryId!,
            priority: _priority,
            title: _title.text.trim(),
            description: _description.text.trim(),
            scheduledStart: _schedule ? _start : null,
            scheduledEnd: _schedule ? _end : null,
            assignedTo: _assignedTo,
            estimatedCostMinor: _estimatedCost.text.isEmpty ? null : ((double.tryParse(_estimatedCost.text) ?? 0) * 100).round(),
            notes: _notes.text.isEmpty ? null : _notes.text,
          );
      if (!mounted) return;
      context.pushReplacement('${AppRoutes.maintenanceTickets}/$id');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final current = isStart ? _start : _end;
    final date = await showDatePicker(context: context, initialDate: current, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = picked;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 2));
      } else {
        _end = picked;
      }
    });
    _checkConflicts();
  }

  /// The numbered section badges use the app's canonical primary green —
  /// same as every other green accent in the app — rather than a one-off
  /// per-module hue.
  Color _accent(AppColorTokens tokens) => tokens.primary;

  Color _priorityColor(AppColorTokens tokens, MaintenancePriority p) => switch (p) {
        // Mirrors the same Low/Medium/High-Critical tones the ticket list and
        // detail screens already use (maintenance_status_chips.dart) — High
        // and Critical share "danger" there too, so the palette doesn't grow
        // a 4th hue just for this selector.
        MaintenancePriority.low => tokens.success,
        MaintenancePriority.medium => tokens.warning,
        MaintenancePriority.high => tokens.destructive,
        MaintenancePriority.critical => tokens.destructive,
      };

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && _loadError == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Maintenance Ticket',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _loading
            ? const _CreateMaintenanceTicketSkeleton()
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : _form(context),
      ),
      bottomNavigationBar: !ready
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.tokens.surface0,
                  border: Border(
                      top: BorderSide(color: context.tokens.borderColor)),
                ),
                child: AuthGradientButton(
                  label: 'Create maintenance ticket',
                  loadingLabel: 'Creating…',
                  isLoading: _submitting,
                  onPressed: _valid && !_submitting ? _submit : null,
                ),
              ),
            ),
    );
  }

  Widget _form(BuildContext context) {
    final tokens = context.tokens;
    final accent = _accent(tokens);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Text('Report an issue and, if it needs court downtime, block the time out.',
            style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
        const SizedBox(height: AppSpacing.lg),

        // ── 1 · Issue Details ────────────────────────────────────────
        _Section(
          n: 1,
          title: 'Issue Details',
          accent: accent,
          children: [
            _labeled(
              'Court',
              required: true,
              child: AppDropdown<String>(
                initialValue: _courtId,
                isExpanded: true,
                hint: const Text('Select court'),
                items: [
                  for (final c in _courts)
                    DropdownMenuItem(value: c.id, child: Text('${c.name} — ${c.sportName}'))
                ],
                onChanged: (v) {
                  setState(() => _courtId = v);
                  _checkConflicts();
                },
              ),
            ),
            _labeled(
              'Issue category',
              required: true,
              child: AppDropdown<String>(
                initialValue: _categoryId,
                isExpanded: true,
                hint: const Text('Select category'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name))
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            _labeled(
              'Priority',
              required: true,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final p in MaintenancePriority.values)
                    _priorityChip(p, color: _priorityColor(tokens, p)),
                ],
              ),
            ),
            _text('Title', _title, required: true, maxLength: 100),
            _text('Description', _description,
                required: true, maxLines: 4, maxLength: 500),
          ],
        ),

        // ── 2 · Schedule ─────────────────────────────────────────────
        _Section(
          n: 2,
          title: 'Schedule',
          accent: accent,
          children: [
            _ToggleRow(
              title: 'Schedule maintenance now',
              subtitle: 'Blocks this court\'s time out on the calendar.',
              value: _schedule,
              onChanged: (v) {
                setState(() => _schedule = v);
                _checkConflicts();
              },
            ),
            if (_schedule) ...[
              const SizedBox(height: AppSpacing.md),
              _labeled(
                'Start',
                child: _PickerField(
                  text: Formatters.dateTimeShort(_start),
                  icon: Icons.edit_calendar_outlined,
                  onTap: () => _pickDateTime(true),
                ),
              ),
              _labeled(
                'End',
                child: _PickerField(
                  text: Formatters.dateTimeShort(_end),
                  icon: Icons.edit_calendar_outlined,
                  onTap: () => _pickDateTime(false),
                ),
              ),
              if (_affectedCount > 0)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warning),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '$_affectedCount existing booking${_affectedCount == 1 ? '' : 's'} overlap this window. They will not be cancelled automatically.',
                          style: TextStyle(fontSize: 12.5, color: tokens.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),

        // ── 3 · Assignment ───────────────────────────────────────────
        _Section(
          n: 3,
          title: 'Assignment',
          accent: accent,
          children: [
            _labeled(
              'Assign staff',
              hint: 'Optional',
              child: AppDropdown<String>(
                initialValue: _assignedTo,
                isExpanded: true,
                hint: const Text('Unassigned'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Unassigned')),
                  for (final s in _staff)
                    DropdownMenuItem(value: s.userId, child: Text('${s.fullName} (${s.role})'))
                ],
                onChanged: (v) => setState(() => _assignedTo = v),
              ),
            ),
            _text('Estimated repair cost', _estimatedCost,
                kb: TextInputType.number, prefix: '₹'),
            _text('Notes', _notes, maxLines: 2),
          ],
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.destructive.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(_error!,
                style: TextStyle(color: tokens.destructive, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  // ── field helpers ───────────────────────────────────────────────────────

  Widget _text(
    String label,
    TextEditingController c, {
    bool required = false,
    TextInputType? kb,
    int maxLines = 1,
    int? maxLength,
    String? prefix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: TextField(
        controller: c,
        keyboardType: kb,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          prefixText: prefix == null ? null : '$prefix ',
        ),
      ),
    );
  }

  Widget _labeled(String label,
      {bool required = false, String? hint, required Widget child}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(
            text: label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary),
            children: required
                ? [
                    TextSpan(
                        text: ' *',
                        style: TextStyle(color: tokens.destructive))
                  ]
                : null,
          )),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(hint,
                style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _priorityChip(MaintenancePriority p, {required Color color}) {
    final tokens = context.tokens;
    final selected = _priority == p;
    return GestureDetector(
      onTap: () => setState(() => _priority = p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSolid(color) : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? tokens.accentSolid(color) : tokens.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? tokens.onAccent(color) : color,
              ),
            ),
            const SizedBox(width: 6),
            Text(p.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? tokens.onAccent(color) : tokens.textPrimary,
                )),
          ],
        ),
      ),
    );
  }
}

/// A numbered, bordered section card — matches the pattern used by every
/// other "create" screen (e.g. Create Membership) so this form doesn't read
/// as a different app.
class _Section extends StatelessWidget {
  const _Section({required this.n, required this.title, required this.accent, required this.children});

  final int n;
  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0.6)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$n',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: tokens.onAccent(accent))),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A single on/off row (schedule toggle) styled like the app's other option
/// rows — a bordered, surface-tinted tile rather than a bare
/// `SwitchListTile` whose thumb colour comes from the ambient Material theme.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: value ? tokens.primary.withValues(alpha: 0.10) : tokens.surface2,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: value ? tokens.primary : tokens.borderColor,
              width: value ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 11.5, color: tokens.textSecondary)),
                    ],
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: tokens.onPrimary,
                activeTrackColor: tokens.primary,
                inactiveThumbColor: tokens.textSecondary,
                inactiveTrackColor: tokens.surface3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable field that looks like the app's other inputs but opens a
/// picker instead of a keyboard — used here for the schedule's start/end
/// date-times.
class _PickerField extends StatelessWidget {
  const _PickerField({required this.text, required this.onTap, this.icon});

  final String text;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: 14),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: TextStyle(color: tokens.textPrimary)),
            ),
            if (icon != null) Icon(icon, size: 18, color: tokens.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder shown while court/category/staff reference
/// data loads — mirrors the real form's single bordered section of field
/// rows plus the sticky submit bar.
class _CreateMaintenanceTicketSkeleton extends StatelessWidget {
  const _CreateMaintenanceTicketSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: const [
        AppSkeleton(width: 260, height: 13),
        SizedBox(height: AppSpacing.lg),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 90, height: 18),
              SizedBox(height: AppSpacing.lg),
              AppSkeleton(width: 60, height: 11),
              SizedBox(height: 6),
              AppSkeleton(height: 44, radius: AppRadius.md),
              SizedBox(height: AppSpacing.lg),
              AppSkeleton(width: 90, height: 11),
              SizedBox(height: 6),
              AppSkeleton(height: 44, radius: AppRadius.md),
              SizedBox(height: AppSpacing.lg),
              AppSkeleton(width: 60, height: 11),
              SizedBox(height: 6),
              AppSkeleton(height: 44, radius: AppRadius.md),
              SizedBox(height: AppSpacing.lg),
              AppSkeleton(width: 40, height: 11),
              SizedBox(height: 6),
              AppSkeleton(height: 44, radius: AppRadius.md),
              SizedBox(height: AppSpacing.lg),
              AppSkeleton(width: 80, height: 11),
              SizedBox(height: 6),
              AppSkeleton(height: 90, radius: AppRadius.md),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(height: 48, radius: AppRadius.pill),
      ],
    );
  }
}
