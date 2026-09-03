import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/picker_chip.dart';

/// Membership revenue received per period — mirrors
/// src/features/memberships/components/membership-revenue-trend.tsx.
/// Horizontal bars, one per bucket, from `get_membership_revenue_timeseries`.
class MembershipRevenueTrend extends ConsumerStatefulWidget {
  const MembershipRevenueTrend({super.key, required this.facilityId});

  final String facilityId;

  @override
  ConsumerState<MembershipRevenueTrend> createState() => _MembershipRevenueTrendState();
}

class _MembershipRevenueTrendState extends ConsumerState<MembershipRevenueTrend> {
  MembershipRevenueGranularity _grain = MembershipRevenueGranularity.month;
  List<MembershipRevenuePoint>? _points;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final points = await ref
          .read(membershipRepositoryProvider)
          .getMembershipRevenueTimeseries(widget.facilityId, granularity: _grain);
      if (!mounted) return;
      setState(() {
        _points = points;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _points = const [];
        _loading = false;
      });
    }
  }

  Future<void> _pickGrain() async {
    final picked = await showPickerSheet<MembershipRevenueGranularity>(
      context: context,
      selected: _grain,
      options: const [
        (value: MembershipRevenueGranularity.day, label: 'By Day'),
        (value: MembershipRevenueGranularity.month, label: 'By Month'),
        (value: MembershipRevenueGranularity.year, label: 'By Year'),
      ],
    );
    if (picked != null && picked != _grain) {
      setState(() => _grain = picked);
      _load();
    }
  }

  String _label(String bucket) {
    final d = DateTime.tryParse(bucket);
    if (d == null) return bucket;
    switch (_grain) {
      case MembershipRevenueGranularity.year:
        return DateFormat('yyyy').format(d);
      case MembershipRevenueGranularity.month:
        return DateFormat('MMM yyyy').format(d);
      case MembershipRevenueGranularity.day:
        return DateFormat('d MMM').format(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    // Display sum of the server's own per-bucket figures — a caption, not a
    // headline, exactly as the web card shows it.
    final total = (points ?? const []).fold<int>(0, (s, p) => s + p.amountInr);
    final max = (points ?? const []).fold<int>(1, (m, p) => p.amountInr > m ? p.amountInr : m);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Membership Revenue Received', style: AppTypography.rowTitle(context)),
                    if (points != null && points.isNotEmpty)
                      Text('${Formatters.currencyInr(total)} across the shown period',
                          style: AppTypography.caption(context)),
                  ],
                ),
              ),
              PickerChip(label: _grainLabel(_grain), onSelect: _pickGrain),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (points == null || points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('No membership revenue received yet.', style: AppTypography.secondary(context)),
            )
          else
            for (final p in points)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(_label(p.bucket), style: AppTypography.caption(context)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Stack(
                          children: [
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: context.tokens.surface2,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Container(
                              height: 16,
                              width: (c.maxWidth * (p.amountInr / max)).clamp(2, c.maxWidth),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(Formatters.currencyInr(p.amountInr),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

String _grainLabel(MembershipRevenueGranularity g) {
  switch (g) {
    case MembershipRevenueGranularity.day:
      return 'By Day';
    case MembershipRevenueGranularity.month:
      return 'By Month';
    case MembershipRevenueGranularity.year:
      return 'By Year';
  }
}
