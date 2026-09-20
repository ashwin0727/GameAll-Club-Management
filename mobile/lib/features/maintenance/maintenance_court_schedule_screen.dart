import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/supabase_provider.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'maintenance_court_options.dart';

class _Slot {
  const _Slot({required this.courtName, required this.start, required this.end, required this.kind, required this.label});
  final String courtName;
  final DateTime start;
  final DateTime end;
  final String kind; // BOOKING | MAINTENANCE
  final String label;
}

/// Maintenance → Court Schedule. Mobile renders a per-day agenda grouped by
/// court — a read over the SAME sources the booking grid uses (bookings +
/// maintenance_blocks, both RLS-scoped direct selects). No second
/// availability algorithm.
class MaintenanceCourtScheduleScreen extends ConsumerStatefulWidget {
  const MaintenanceCourtScheduleScreen({super.key});

  @override
  ConsumerState<MaintenanceCourtScheduleScreen> createState() => _State();
}

class _State extends ConsumerState<MaintenanceCourtScheduleScreen> {
  DateTime _day = DateTime.now();
  bool _loading = true;
  String? _error;
  Map<String, List<_Slot>> _byCourt = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseClientProvider);
      final courts = await loadMaintenanceCourtOptions(ref, facility.id);
      final courtName = {for (final c in courts) c.id: c.name};
      final dayStart = DateTime(_day.year, _day.month, _day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final bookings = await client
          .from('bookings')
          .select('court_id, start_time, end_time, customer_type, guest_name')
          .eq('facility_id', facility.id)
          .inFilter('status', ['pending', 'confirmed'])
          .gte('start_time', dayStart.toIso8601String())
          .lt('start_time', dayEnd.toIso8601String());

      final blocks = await client
          .from('maintenance_blocks')
          .select('court_id, start_time, end_time')
          .eq('facility_id', facility.id)
          .eq('status', 'ACTIVE')
          .gte('start_time', dayStart.subtract(const Duration(days: 1)).toIso8601String())
          .lt('start_time', dayEnd.toIso8601String());

      final grouped = <String, List<_Slot>>{};
      for (final c in courts) {
        grouped[c.name] = [];
      }
      for (final b in bookings as List) {
        final m = b as Map<String, dynamic>;
        final name = courtName[m['court_id']] ?? 'Court';
        grouped.putIfAbsent(name, () => []).add(_Slot(
              courtName: name,
              start: DateTime.parse(m['start_time'] as String),
              end: DateTime.parse(m['end_time'] as String),
              kind: 'BOOKING',
              label: m['customer_type'] == 'GUEST' ? (m['guest_name'] as String? ?? 'Guest') : 'Member',
            ));
      }
      for (final b in blocks as List) {
        final m = b as Map<String, dynamic>;
        final start = DateTime.parse(m['start_time'] as String);
        final end = DateTime.parse(m['end_time'] as String);
        if (end.isBefore(dayStart)) continue;
        final name = courtName[m['court_id']] ?? 'Court';
        grouped.putIfAbsent(name, () => []).add(_Slot(courtName: name, start: start, end: end, kind: 'MAINTENANCE', label: 'Maintenance'));
      }
      for (final list in grouped.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }
      if (!mounted) return;
      setState(() {
        _byCourt = grouped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load the schedule.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Court Schedule'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
          Center(child: Text('${_day.day}/${_day.month}')),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const _MaintenanceCourtScheduleSkeleton()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        for (final entry in _byCourt.entries) ...[
                          SectionHeader(title: entry.key),
                          const SizedBox(height: AppSpacing.xs),
                          AppCard(
                            child: entry.value.isEmpty
                                ? Text('Available all day', style: Theme.of(context).textTheme.bodySmall)
                                : Column(
                                    children: [
                                      for (final s in entry.value)
                                        ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            s.kind == 'MAINTENANCE' ? Icons.build : Icons.event,
                                            color: s.kind == 'MAINTENANCE' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                                          ),
                                          title: Text(s.label),
                                          subtitle: Text('${_hm(s.start)} – ${_hm(s.end)}'),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  String _hm(DateTime d) {
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$h:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// Structure-shaped placeholder shown while the day's schedule loads —
/// mirrors the real body's repeated "court heading + timeline card" sections.
class _MaintenanceCourtScheduleSkeleton extends StatelessWidget {
  const _MaintenanceCourtScheduleSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        _CourtSection(),
        SizedBox(height: AppSpacing.md),
        _CourtSection(),
        SizedBox(height: AppSpacing.md),
        _CourtSection(),
      ],
    );
  }
}

class _CourtSection extends StatelessWidget {
  const _CourtSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSkeleton(width: 140, height: 16),
        const SizedBox(height: AppSpacing.xs),
        SkeletonCard(
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == 2 ? 0 : AppSpacing.sm),
                  child: Row(
                    children: const [
                      AppSkeleton(width: 24, height: 24, radius: 12),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppSkeleton(width: 110, height: 13),
                            SizedBox(height: 6),
                            AppSkeleton(width: 90, height: 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
