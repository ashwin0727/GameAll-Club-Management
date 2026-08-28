import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/finance.dart';
import '../../shared/widgets/picker_chip.dart';

/// Mirrors src/features/finance/components/date-range-picker.tsx.
///
/// Every preset resolves to actual dates on the BACKEND — facility-timezone
/// aware, via `resolve_finance_date_range` (0024_finance.sql). This widget
/// only ever picks WHICH preset (or which explicit start/end for CUSTOM); it
/// never computes "today" or a week boundary itself, so a device whose clock
/// or timezone differs from the facility's cannot shift what a range means
/// (spec §"Date Range" / §"Date/Time").
///
/// Laid out in a [Wrap] so the preset chip and the two custom-date chips
/// reflow onto their own lines at 320dp or at large system font sizes
/// instead of overflowing.
class FinanceDateRangePicker extends StatelessWidget {
  const FinanceDateRangePicker({super.key, required this.value, required this.onChanged});

  final FinanceDateRange value;
  final ValueChanged<FinanceDateRange> onChanged;

  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');

  Future<void> _pickPreset(BuildContext context) async {
    final picked = await showPickerSheet<FinanceDateRangePreset>(
      context: context,
      selected: value.preset,
      options: FinanceDateRangePreset.values.map((p) => (value: p, label: p.label)).toList(),
    );
    if (picked != null && picked != value.preset) {
      onChanged(value.copyWith(preset: picked));
    }
  }

  /// The picked day is sent as a plain `yyyy-MM-dd` string — a Postgres
  /// `date` literal, which `resolve_finance_date_range` then interprets in
  /// the facility's timezone. Deliberately not an instant: sending a UTC
  /// timestamp here is exactly how an off-by-one-day range happens.
  Future<void> _pickDate(BuildContext context, {required bool isStart}) async {
    final existing = isStart ? value.startDate : value.endDate;
    final initial = existing != null ? DateTime.parse(existing) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      helpText: isStart ? 'Start date' : 'End date',
    );
    if (picked == null) return;
    final formatted = _isoDate.format(picked);
    onChanged(
      isStart
          ? FinanceDateRange(preset: value.preset, startDate: formatted, endDate: value.endDate)
          : FinanceDateRange(preset: value.preset, startDate: value.startDate, endDate: formatted),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PickerChip(label: value.preset.label, onSelect: () => _pickPreset(context)),
        if (value.preset == FinanceDateRangePreset.custom) ...[
          PickerChip(
            label: value.startDate ?? 'Start date',
            icon: Icons.calendar_today,
            onSelect: () => _pickDate(context, isStart: true),
          ),
          Text('to', style: AppTypography.secondary(context)),
          PickerChip(
            label: value.endDate ?? 'End date',
            icon: Icons.calendar_today,
            onSelect: () => _pickDate(context, isStart: false),
          ),
        ],
      ],
    );
  }
}