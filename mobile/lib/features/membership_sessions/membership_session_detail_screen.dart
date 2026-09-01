import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership_session_dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'batch_members_sheet.dart';
import 'membership_sessions_screen.dart' show hhmm, daysLabel;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _durationLabel(String start, String end) {
  List<int> p(String t) {
    final parts = t.split(':');
    return [int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0, int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0];
  }

  final s = p(start);
  final e = p(end);
  final mins = e[0] * 60 + e[1] - (s[0] * 60 + s[1]);
  if (mins <= 0) return '—';
  final h = mins ~/ 60;
  final m = mins % 60;
  return [if (h > 0) '$h Hour${h > 1 ? 's' : ''}', if (m > 0) '$m Min'].join(' ');
}

/// Full-page detail for one recurring membership session — a single
/// scrolling layout (hero, schedule, capacity, members, guest slots,
/// notes, link, session details, activity). Mirrors the web
/// `session-detail-page.tsx`.
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
  List<MembershipSessionMemberRow>? _members;
  List<MembershipSessionActivity>? _activity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _detail == null;
      _error = null;
    });
    final repo = ref.read(membershipSessionRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.getSessionDetail(widget.batchId),
        repo.getSessionMembers(widget.batchId),
        repo.listSessionActivity(widget.batchId),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as MembershipSessionDetail;
        _members = results[1] as List<MembershipSessionMemberRow>;
        _activity = results[2] as List<MembershipSessionActivity>;
        _isLoading = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _blockToday() async {
    try {
      await ref.read(membershipSessionRepositoryProvider).blockDate(widget.batchId, _iso(DateTime.now()));
      _toast("Today's occurrence blocked");
      await _load();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _duplicate() async {
    try {
      await ref.read(membershipSessionRepositoryProvider).duplicateSession(widget.batchId);
      _toast('Session duplicated');
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _toggleActive() async {
    final d = _detail;
    if (d == null) return;
    try {
      await ref.read(membershipSessionRepositoryProvider).updateBatch(widget.batchId, isActive: !d.isActive);
      await _load();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _openEdit() async {
    final d = _detail;
    if (d == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditSessionSheet(batchId: widget.batchId, detail: d),
    );
    if (changed == true) await _load();
  }

  Future<void> _openReleaseGuestSlots() async {
    final d = _detail;
    if (d == null) return;
    final released = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReleaseGuestSlotsSheet(batchId: widget.batchId, detail: d),
    );
    if (released == true) await _load();
  }

  Future<void> _openAddMember() async {
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
      _toast(e.message);
    }
  }

  Future<void> _removeMember(String memberId) async {
    try {
      await ref.read(membershipSessionRepositoryProvider).removeBatchMember(widget.batchId, memberId);
      await _load();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _editNotes() async {
    final d = _detail;
    if (d == null) return;
    final controller = TextEditingController(text: d.notes ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Notes'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'e.g. Please be on time. Carry your own shuttlecocks.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      try {
        await ref.read(membershipSessionRepositoryProvider).setSessionNotes(widget.batchId, controller.text.trim());
        await _load();
      } on AppException catch (e) {
        _toast(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Session Details'),
        actions: [
          if (d != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _openEdit();
                  case 'release':
                    _openReleaseGuestSlots();
                  case 'block':
                    _blockToday();
                  case 'duplicate':
                    _duplicate();
                  case 'toggle':
                    _toggleActive();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Session')),
                const PopupMenuItem(value: 'release', child: Text('Release Guest Slots')),
                const PopupMenuItem(value: 'block', child: Text("Block today's occurrence")),
                const PopupMenuItem(value: 'duplicate', child: Text('Duplicate session')),
                PopupMenuItem(value: 'toggle', child: Text(d.isActive ? 'Pause session' : 'Activate session')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading session…')
            : _error != null && d == null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ResponsivePage(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _hero(d!),
                          const SizedBox(height: AppSpacing.sm),
                          _scheduleCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _capacityCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _membersCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _guestSlotsCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _notesCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _linkCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _sessionDetailsCard(d),
                          const SizedBox(height: AppSpacing.sm),
                          _activityCard(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    ),
                  ),
      ),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openEdit,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit Session'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openReleaseGuestSlots,
                        icon: const Icon(Icons.group_add, size: 16),
                        label: const Text('Release Slots'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _hero(MembershipSessionDetail d) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.event_repeat, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: Theme.of(context).textTheme.titleMedium),
                    if (d.notes != null && d.notes!.isNotEmpty)
                      Text(d.notes!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
              StatusBadge(
                label: d.isActive ? 'Active' : 'Paused',
                tone: d.isActive ? StatusTone.success : StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _meta('Session ID', 'SES${d.batchId.substring(0, 3).toUpperCase()}'),
              _meta('Sport', d.sportName),
              _meta('Court', d.courtName),
              _meta('Capacity', '${d.capacity} Players'),
              _meta('Session Type', 'Membership Protected'),
              _meta('Guest Release', 'Allowed'),
              if (d.createdByName != null) _meta('Created By', d.createdByName!),
              _meta('Last Updated', Formatters.dateShort(d.updatedAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _scheduleCard(MembershipSessionDetail d) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Schedule Information', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text('Days', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xs),
          Text(daysLabel(d.daysOfWeek), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _meta('Time', '${hhmm(d.startTime)} – ${hhmm(d.endTime)}'),
              _meta('Start Date', Formatters.dateShort(d.createdAt)),
              _meta('End Date', 'No Expiry'),
              _meta('Duration', _durationLabel(d.startTime, d.endTime)),
              _meta('Recurrence', 'Every Week'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capacityCard(MembershipSessionDetail d) {
    final utilization = d.capacity > 0 ? ((d.rosterCount / d.capacity) * 100).round() : 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Capacity & Utilization (Today)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: _CapacityDonut(
              capacity: d.capacity,
              members: d.rosterCount,
              guestsBooked: d.guestsBookedToday,
              availableToRelease: d.availableToRelease,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _legend(AppColors.success, 'Members Assigned', d.rosterCount),
          _legend(AppColors.electricBlue, 'Guests Booked', d.guestsBookedToday),
          _legend(AppColors.muted, 'Available to Release', d.availableToRelease),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('Utilization', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
              const Spacer(),
              Text('$utilization%', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: (utilization.clamp(0, 100)) / 100,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label, int value) {
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

  Widget _membersCard(MembershipSessionDetail d) {
    final members = _members ?? const <MembershipSessionMemberRow>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Members Assigned (${members.length} / ${d.capacity})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: members.length >= d.capacity ? null : _openAddMember,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Member'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No members assigned yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            )
          else
            ...members.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.fullName, style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                              '${m.phone} · added ${Formatters.dateShort(m.addedOn)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(
                        label: m.status == 'ACTIVE' ? 'Active' : 'Inactive',
                        tone: m.status == 'ACTIVE' ? StatusTone.success : StatusTone.neutral,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Remove from session',
                        onPressed: () => _removeMember(m.memberId),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _guestSlotsCard(MembershipSessionDetail d) {
    final availableToBook = math.max(0, d.releasedToday - d.guestsBookedToday);
    final tiles = <({String label, int value, bool highlight})>[
      (label: 'Total Capacity', value: d.capacity, highlight: false),
      (label: 'Members Assigned', value: d.rosterCount, highlight: false),
      (label: 'Guest Released', value: d.releasedToday, highlight: false),
      (label: 'Guests Booked', value: d.guestsBookedToday, highlight: false),
      (label: 'Available to Book', value: availableToBook, highlight: true),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Guest Slots (Today)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: tiles
                .map((t) => Container(
                      width: 96,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: t.highlight ? AppColors.primary : AppColors.border),
                        color: t.highlight ? AppColors.primary.withValues(alpha: 0.06) : null,
                      ),
                      child: Column(
                        children: [
                          Text('${t.value}', style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            t.label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Guest slots are released by the owner and available for booking on a first come first serve basis.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _notesCard(MembershipSessionDetail d) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Session Notes', style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(onPressed: _editNotes, icon: const Icon(Icons.edit, size: 14), label: const Text('Edit')),
            ],
          ),
          Text(
            (d.notes == null || d.notes!.isEmpty) ? 'No notes for this session yet.' : d.notes!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _linkCard(MembershipSessionDetail d) {
    final link = 'https://gameall.club/join/${d.facilityId}?session=${d.batchId}';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session Link', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Share this link to allow members to register for this session.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  _toast('Link copied');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sessionDetailsCard(MembershipSessionDetail d) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          _row('Facility', d.facilityName ?? '—'),
          _row('Address', d.facilityAddress ?? '—'),
          _row('Session Type', 'Membership Protected'),
          _row('Guest Release', 'Allowed'),
          _row('Payment Type', 'Included in Membership'),
          _row('Created By', d.createdByName ?? '—'),
          _row('Created On', Formatters.dateTimeShort(d.createdAt)),
          _row('Last Updated', Formatters.dateTimeShort(d.updatedAt)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _activityCard() {
    final rows = _activity;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity Timeline', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (rows == null)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Text('No activity yet.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted))
          else
            ...rows.map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5, right: AppSpacing.sm),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.detail, style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                              '${a.actor != null ? '${a.actor} · ' : ''}${Formatters.dateTimeShort(a.at)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
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
// Capacity donut
// ---------------------------------------------------------------------------

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
              Text('Capacity', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
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
// Edit session
// ---------------------------------------------------------------------------

const List<({int value, String label})> _dayOpts = [
  (value: 1, label: 'Mon'),
  (value: 2, label: 'Tue'),
  (value: 3, label: 'Wed'),
  (value: 4, label: 'Thu'),
  (value: 5, label: 'Fri'),
  (value: 6, label: 'Sat'),
  (value: 0, label: 'Sun'),
];

class _EditSessionSheet extends ConsumerStatefulWidget {
  const _EditSessionSheet({required this.batchId, required this.detail});

  final String batchId;
  final MembershipSessionDetail detail;

  @override
  ConsumerState<_EditSessionSheet> createState() => _EditSessionSheetState();
}

class _EditSessionSheetState extends ConsumerState<_EditSessionSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.detail.name);
  late final TextEditingController _capacity = TextEditingController(text: '${widget.detail.capacity}');
  late final List<int> _days = [...widget.detail.daysOfWeek];
  late TimeOfDay _start = _parse(widget.detail.startTime);
  late TimeOfDay _end = _parse(widget.detail.endTime);
  late bool _active = widget.detail.isActive;
  bool _saving = false;
  String? _error;

  static TimeOfDay _parse(String t) {
    final p = t.split(':');
    return TimeOfDay(hour: int.tryParse(p.isNotEmpty ? p[0] : '0') ?? 0, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cap = int.tryParse(_capacity.text.trim());
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter a session name.');
      return;
    }
    if (_days.isEmpty) {
      setState(() => _error = 'Select at least one day.');
      return;
    }
    if (cap == null || cap <= 0) {
      setState(() => _error = 'Enter a valid capacity.');
      return;
    }
    if (_fmt(_end).compareTo(_fmt(_start)) <= 0) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(membershipSessionRepositoryProvider).updateBatch(
            widget.batchId,
            name: _name.text.trim(),
            daysOfWeek: _days,
            startTime: _fmt(_start),
            endTime: _fmt(_end),
            capacity: cap,
            isActive: _active,
          );
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Session', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Session name')),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              children: _dayOpts
                  .map((d) => FilterChip(
                        label: Text(d.label),
                        selected: _days.contains(d.value),
                        onSelected: (s) => setState(() => s ? _days.add(d.value) : _days.remove(d.value)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: _start);
                      if (t != null) setState(() => _start = t);
                    },
                    child: Text('From ${_fmt(_start)}'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: _end);
                      if (t != null) setState(() => _end = t);
                    },
                    child: Text('To ${_fmt(_end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacity'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Session is active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Release guest slots
// ---------------------------------------------------------------------------

class _ReleaseGuestSlotsSheet extends ConsumerStatefulWidget {
  const _ReleaseGuestSlotsSheet({required this.batchId, required this.detail});

  final String batchId;
  final MembershipSessionDetail detail;

  @override
  ConsumerState<_ReleaseGuestSlotsSheet> createState() => _ReleaseGuestSlotsSheetState();
}

class _ReleaseGuestSlotsSheetState extends ConsumerState<_ReleaseGuestSlotsSheet> {
  final _count = TextEditingController(text: '1');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    final n = int.tryParse(_count.text.trim());
    final max = widget.detail.availableToRelease;
    if (n == null || n <= 0) {
      setState(() => _error = 'Enter a valid number of slots.');
      return;
    }
    if (n > max) {
      setState(() => _error = 'Only $max slot(s) can be released today.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(membershipSessionRepositoryProvider);
    try {
      final sessionId = await repo.getOrCreateSession(widget.batchId, _iso(DateTime.now()));
      await repo.releaseCapacity(sessionId, n);
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Release Guest Slots (Today)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (!d.runsToday)
            Text('This session is not scheduled to run today.', style: Theme.of(context).textTheme.bodySmall)
          else ...[
            Text(
              'Up to ${d.availableToRelease} unused slot(s) can be released for guest booking today.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Slots to release'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || d.availableToRelease == 0 ? null : _release,
                child: Text(_busy ? 'Releasing…' : 'Release'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}