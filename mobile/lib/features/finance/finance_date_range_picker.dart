import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/finance.dart';

final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
final DateFormat _shown = DateFormat('d MMM yyyy');

/// The current calendar month, first day → today, as an explicit range.
/// Mirrors the web's default (`src/features/finance/day-range.ts`).
FinanceDateRange currentMonthRange([DateTime? now]) {
  final n = now ?? DateTime.now();
  return FinanceDateRange(
    preset: FinanceDateRangePreset.custom,
    startDate: _isoDate.format(DateTime(n.year, n.month, 1)),
    endDate: _isoDate.format(DateTime(n.year, n.month, n.day)),
  );
}

/// Mirrors the web `DayRangeFilter`: a From and a To date, and the range only
/// changes when **Apply** is pressed — so picking the start of a range never
/// fires a request for a half-chosen window.
///
/// The picked day is sent as a plain `yyyy-MM-dd` string — a Postgres `date`
/// literal that `resolve_finance_date_range` interprets in the facility's
/// timezone (never an instant, which is how off-by-one ranges happen).
///
/// [trailing] sits beside Apply (e.g. an Export button).
class FinanceDateRangePicker extends StatefulWidget {
  const FinanceDateRangePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  final FinanceDateRange value;
  final ValueChanged<FinanceDateRange> onChanged;
  final Widget? trailing;

  @override
  State<FinanceDateRangePicker> createState() => _FinanceDateRangePickerState();
}

class _FinanceDateRangePickerState extends State<FinanceDateRangePicker> {
  late String? _from = widget.value.startDate;
  late String? _to = widget.value.endDate;

  @override
  void didUpdateWidget(covariant FinanceDateRangePicker old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = widget.value.startDate;
      _to = widget.value.endDate;
    }
  }

  bool get _valid => _from != null && _to != null && _from!.compareTo(_to!) <= 0;
  bool get _dirty => _from != widget.value.startDate || _to != widget.value.endDate;

  Future<void> _pick({required bool isFrom}) async {
    final existing = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing != null ? DateTime.parse(existing) : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      helpText: isFrom ? 'From date' : 'To date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = _isoDate.format(picked);
      } else {
        _to = _isoDate.format(picked);
      }
    });
  }

  void _apply() {
    widget.onChanged(FinanceDateRange(
      preset: FinanceDateRangePreset.custom,
      startDate: _from,
      endDate: _to,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final invalid = _from != null && _to != null && !_valid;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Expanded(child: _DateField(label: 'From', value: _from, onTap: () => _pick(isFrom: true))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _DateField(label: 'To', value: _to, onTap: () => _pick(isFrom: false))),
            ],
          ),
          if (invalid) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('The From date must be on or before the To date.',
                style: TextStyle(color: tokens.destructive, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _valid && _dirty ? _apply : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Apply'),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                widget.trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: '$label date',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: tokens.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: tokens.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                    Text(
                      value == null ? 'Select' : _shown.format(DateTime.parse(value!)),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: value == null ? AppColors.muted : tokens.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
