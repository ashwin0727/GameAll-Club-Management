import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/membership_session_dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import 'batch_members_sheet.dart';
import 'membership_sessions_screen.dart' show hhmm, daysLabel;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Detail view for one recurring membership session — tabbed
/// Overview / Members / Occurrences / Bookings / Activity, with a capacity
/// donut and quick actions. Mirrors the web `session-detail-drawer.tsx`.
class MembershipSessionDetailScreen extends ConsumerStatefulWidget {
  const MembershipSessionDetailScreen({
    super.key,
    required this.facilityId,
    required this.batchId,
    required this.title,
  });

  final String facilityId;
  final String batchId;
  final String title;

  @override
  ConsumerState<MembershipSessionDetailScreen> createState() => _MembershipSessionDetailScreenState();
}

class _MembershipSessionDetailScreenState extends ConsumerState<MembershipSessionDetailScreen> {
  bool _isLoading = true;
  String? _error;
  MembershipSessionDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await ref.read(membershipSessionRepositoryProvider).getSessionDetail(widget.batchId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_detail?.name ?? widget.title),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Members'),
              Tab(text: 'Occurrences'),
              Tab(text: 'Bookings'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: SafeArea(
          child: _isLoading
              ? const LoadingView(message: 'Loading session…')
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : TabBarView(
                      children: [
                        _OverviewTab(detail: _detail!, facilityId: widget.facilityId, onChanged: _load),
                        _MembersTab(batchId: widget.batchId, facilityId: widget.facilityId),
                        _OccurrencesTab(batchId: widget.batchId, onChanged: _load),
                        _BookingsTab(batchId: widget.batchId),
                        _ActivityTab(batchId: widget.batchId),
                      ],
                    ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.detail, required this.facilityId, required this.onChanged});

  final MembershipSessionDetail detail;
  final String facilityId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Capacity Overview', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: _CapacityDonut(
                    capacity: detail.capacity,
                    members: detail.rosterCount,
                    guestsBooked: detail.guestsBookedToday,
                    availableToRelease: detail.availableToRelease,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _legend(context, AppColors.success, 'Members', detail.rosterCount),
                _legend(context, AppColors.electricBlue, 'Guests Booked', detail.guestsBookedToday),
                _legend(context, AppColors.muted, 'Available to Release', detail.availableToRelease),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _meta(context, 'Sport', detail.sportName),
                _meta(context, 'Court', detail.courtName),
                if (detail.planName != null) _meta(context, 'Plan', detail.planName!),
                _meta(context, 'Schedule', '${daysLabel(detail.daysOfWeek)} · ${hhmm(detail.startTime)}–${hhmm(detail.endTime)}'),
                _meta(context, 'Capacity', '${detail.capacity} per occurrence'),
                _meta(context, 'Status', detail.isActive ? 'Active' : 'Paused'),
                if (detail.createdByName != null) _meta(context, 'Created by', detail.createdByName!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _occurrenceWidget(
                  context,
                  "Today's Occurrence",
                  detail.runsToday ? 'Runs today' : 'Not scheduled today',
                  detail.runsToday
                      ? '${detail.rosterCount}/${detail.capacity} members · ${detail.guestsBookedToday}/${detail.releasedToday} guests'
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _occurrenceWidget(
                  context,
                  'Next Occurrence',
                  detail.nextOccurrenceDate != null ? Formatters.dateShort(detail.nextOccurrenceDate!) : '—',
                  null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick Actions', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _addMember(context, ref),
                      icon: const Icon(Icons.person_add_alt, size: 16),
                      label: const Text('Add Member'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _blockToday(context, ref),
                      icon: const Icon(Icons.event_busy, size: 16),
                      label: const Text('Block Today'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _duplicate(context, ref),
                      icon: const Icon(Icons.copy_all, size: 16),
                      label: const Text('Duplicate Session'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Text('$value', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _occurrenceWidget(BuildContext context, String title, String value, String? sub) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    try {
      final batches = await ref.read(membershipSessionRepositoryProvider).getFacilityBatches(facilityId);
      final batch = batches.where((b) => b.id == detail.batchId).firstOrNull;
      if (batch == null || !context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => BatchMembersSheet(facilityId: facilityId, batch: batch),
      );
      onChanged();
    } on AppException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _blockToday(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(membershipSessionRepositoryProvider).blockDate(detail.batchId, _iso(DateTime.now()));
      messenger.showSnackBar(const SnackBar(content: Text("Today's occurrence blocked")));
      onChanged();
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(membershipSessionRepositoryProvider).duplicateSession(detail.batchId);
      messenger.showSnackBar(const SnackBar(content: Text('Session duplicated')));
      if (context.mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _CapacityDonut extends StatelessWidget {
  const _CapacityDonut({
    required this.capacity,
    required this.members,
    required this.guestsBooked,
    required this.availableToRelease,
  });

  final int capacity;
  final int members;
  final int guestsBooked;
  final int availableToRelease;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: CustomPaint(
        painter: _DonutPainter(
          segments: [
            (members.toDouble(), AppColors.success),
            (guestsBooked.toDouble(), AppColors.electricBlue),
            (availableToRelease.toDouble(), AppColors.muted),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$capacity', style: Theme.of(context).textTheme.titleLarge),
              Text('capacity', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments});

  final List<(double, Color)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.$1);
    final rect = Offset.zero & size;
    const stroke = 16.0;
    final arcRect = rect.deflate(stroke / 2);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.border;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, bg);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final seg in segments) {
      if (seg.$1 <= 0) continue;
      final sweep = (seg.$1 / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = seg.$2;
      canvas.drawArc(arcRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Members
// ---------------------------------------------------------------------------

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({required this.batchId, required this.facilityId});

  final String batchId;
  final String facilityId;

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  List<MembershipBatchMember>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await ref.read(membershipSessionRepositoryProvider).getBatchMembers(widget.batchId);
      if (mounted) setState(() => _members = members);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openManage() async {
    try {
      final batches = await ref.read(membershipSessionRepositoryProvider).getFacilityBatches(widget.facilityId);
      final batch = batches.where((b) => b.id == widget.batchId).firstOrNull;
      if (batch == null || !mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => BatchMembersSheet(facilityId: widget.facilityId, batch: batch),
      );
      await _load();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _openManage,
              icon: const Icon(Icons.manage_accounts, size: 16),
              label: const Text('Manage Roster'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.destructive)),
          if (members == null)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
          else if (members.isEmpty)
            const EmptyStateView(message: 'No members on this session yet.')
          else
            ...members.map((m) => AppCard(
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18, color: AppColors.muted),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Member ${m.memberId.substring(0, m.memberId.length < 8 ? m.memberId.length : 8)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Occurrences
// ---------------------------------------------------------------------------

class _OccurrencesTab extends ConsumerStatefulWidget {
  const _OccurrencesTab({required this.batchId, required this.onChanged});

  final String batchId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_OccurrencesTab> createState() => _OccurrencesTabState();
}

class _OccurrencesTabState extends ConsumerState<_OccurrencesTab> {
  List<MembershipSessionOccurrence>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(membershipSessionRepositoryProvider).listOccurrences(widget.batchId);
      if (mounted) setState(() => _rows = rows);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggleBlock(MembershipSessionOccurrence o) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(membershipSessionRepositoryProvider);
    try {
      if (o.isBlocked) {
        await repo.unblockDate(widget.batchId, _iso(o.occurrenceDate));
      } else {
        await repo.blockDate(widget.batchId, _iso(o.occurrenceDate));
      }
      await _load();
      widget.onChanged();
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.destructive)),
          if (rows == null)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            const EmptyStateView(message: 'No upcoming occurrences.')
          else
            ...rows.map((o) => AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Formatters.dateShort(o.occurrenceDate), style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                              o.isBlocked
                                  ? 'Blocked${o.blockReason != null ? ' · ${o.blockReason}' : ''}'
                                  : '${o.memberCount} members · ${o.guestCount}/${o.releasedCapacity} guests',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleBlock(o),
                        child: Text(o.isBlocked ? 'Unblock' : 'Block'),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookings
// ---------------------------------------------------------------------------

class _BookingsTab extends ConsumerStatefulWidget {
  const _BookingsTab({required this.batchId});

  final String batchId;

  @override
  ConsumerState<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<_BookingsTab> {
  List<MembershipSessionBookingRow>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(membershipSessionRepositoryProvider).listSessionBookings(widget.batchId);
      if (mounted) setState(() => _rows = rows);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.destructive)),
          if (rows == null)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            const EmptyStateView(message: 'No bookings yet.')
          else
            ...rows.map((b) => AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.participantName, style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                              '${Formatters.dateShort(b.sessionDate)} · ${b.participantType} · ${b.slotSource}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      if (b.amountMinor != null)
                        Text(Formatters.currencyInr(b.amountMinor! / 100), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

class _ActivityTab extends ConsumerStatefulWidget {
  const _ActivityTab({required this.batchId});

  final String batchId;

  @override
  ConsumerState<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<_ActivityTab> {
  List<MembershipSessionActivity>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(membershipSessionRepositoryProvider).listSessionActivity(widget.batchId);
      if (mounted) setState(() => _rows = rows);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.destructive)),
          if (rows == null)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            const EmptyStateView(message: 'No activity recorded.')
          else
            ...rows.map((a) => AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.detail, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${a.actor != null ? '${a.actor} · ' : ''}${Formatters.dateTimeShort(a.at)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}