/// Reports & Analytics — the shared filter controls (Phase 9.1).
///
/// The mobile stand-in for the web's `<AnalyticsFilterBar>`: a row of
/// [PickerChip]s (date range / sport / court) that each open a
/// `showModalBottomSheet` option list, following the Owner Dashboard
/// pattern. No facility chip — the session tracks one facility.
///
/// Controlled: it holds no filter state, it renders [filter] and calls
/// [onChanged] with the next one. Sport/court option lists are loaded once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/models/analytics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/picker_chip.dart';

class _SportOption {
  const _SportOption(this.id, this.name);
  final String id;
  final String name;
}

class _CourtOption {
  const _CourtOption(this.id, this.name, this.facilitySportId);
  final String id;
  final String name;
  final String facilitySportId;
}

class AnalyticsFilterControls extends ConsumerStatefulWidget {
  const AnalyticsFilterControls({
    super.key,
    required this.facilityId,
    required this.filter,
    required this.onChanged,
  });

  final String facilityId;
  final AnalyticsFilter filter;
  final ValueChanged<AnalyticsFilter> onChanged;

  @override
  ConsumerState<AnalyticsFilterControls> createState() => _AnalyticsFilterControlsState();
}

class _AnalyticsFilterControlsState extends ConsumerState<AnalyticsFilterControls> {
  List<_SportOption> _sports = const [];
  List<_CourtOption> _courts = const [];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final areasRepo = ref.read(playingAreaRepositoryProvider);
      final catalog = await sportsRepo.getActiveSports();
      final facilitySports = await sportsRepo.getFacilitySports(widget.facilityId);
      final areas = await areasRepo.getPlayingAreas(widget.facilityId);
      if (!mounted) return;
      setState(() {
        _sports = facilitySports.map((fs) {
          final name = fs.customSportName?.trim().isNotEmpty == true
              ? fs.customSportName!
              : (catalog.where((c) => c.id == fs.sportId).map((c) => c.name).firstOrNull ?? 'Sport');
          return _SportOption(fs.id, name);
        }).toList();
        _courts = areas.map((a) => _CourtOption(a.id, a.name, a.facilitySportId)).toList();
      });
    } catch (_) {
      // A failed option load leaves the chips showing "All" — the report
      // itself still works facility-wide.
    }
  }

  String get _sportLabel => widget.filter.facilitySportId == null
      ? 'All Sports'
      : _sports
              .where((s) => s.id == widget.filter.facilitySportId)
              .map((s) => s.name)
              .firstOrNull ??
          'Sport';

  String get _courtLabel => widget.filter.courtId == null
      ? 'All Courts'
      : _courts.where((c) => c.id == widget.filter.courtId).map((c) => c.name).firstOrNull ?? 'Court';

  String get _dateLabel {
    final f = widget.filter;
    if (f.preset == AnalyticsPreset.custom && f.startDate != null && f.endDate != null) {
      return '${f.startDate} – ${f.endDate}';
    }
    return f.preset.label;
  }

  Future<void> _pickPreset() async {
    final picked = await showModalBottomSheet<AnalyticsPreset>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in kAnalyticsPresets)
              ListTile(
                title: Text(p.label),
                trailing: p == widget.filter.preset ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == AnalyticsPreset.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (range == null) return;
      widget.onChanged(
        widget.filter.copyWith(
          preset: AnalyticsPreset.custom,
          startDate: _iso(range.start),
          endDate: _iso(range.end),
        ),
      );
      return;
    }
    widget.onChanged(widget.filter.copyWith(preset: picked));
  }

  Future<void> _pickSport() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: const Text('All Sports'), onTap: () => Navigator.pop(ctx, '')),
            for (final s in _sports)
              ListTile(title: Text(s.name), onTap: () => Navigator.pop(ctx, s.id)),
          ],
        ),
      ),
    );
    if (picked == null) return;
    widget.onChanged(
      widget.filter.copyWith(
        facilitySportId: picked.isEmpty ? null : picked,
        courtId: null,
      ),
    );
  }

  Future<void> _pickCourt() async {
    final visible = widget.filter.facilitySportId == null
        ? _courts
        : _courts.where((c) => c.facilitySportId == widget.filter.facilitySportId).toList();
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: const Text('All Courts'), onTap: () => Navigator.pop(ctx, '')),
            for (final c in visible)
              ListTile(title: Text(c.name), onTap: () => Navigator.pop(ctx, c.id)),
          ],
        ),
      ),
    );
    if (picked == null) return;
    widget.onChanged(widget.filter.copyWith(courtId: picked.isEmpty ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        PickerChip(label: _dateLabel, onSelect: _pickPreset),
        PickerChip(label: _sportLabel, onSelect: _pickSport),
        PickerChip(label: _courtLabel, onSelect: _pickCourt),
      ],
    );
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
