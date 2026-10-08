import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/page_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/guest_booking_dashboard.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'member_schedule.dart';
import 'membership_detail_screen.dart';

/// Memberships → Membership Schedule — mirrors
/// src/features/memberships/components/member-schedule-page.tsx.
///
/// Pick a member and see their allocated court slots across a week (or a single day), alongside the
/// guest bookings on the same court(s) so staff can see what else is happening there. The web draws
/// a time grid; on a phone each day is a short list of slots, which reads better at this width.
/// Maintenance blocks and closed days are not overlaid here.
class MemberScheduleScreen extends ConsumerStatefulWidget {
  const MemberScheduleScreen({super.key});

  @override
  ConsumerState<MemberScheduleScreen> createState() => _MemberScheduleScreenState();
}

class _MemberScheduleScreenState extends ConsumerState<MemberScheduleScreen> {
  List<MemberScheduleSummary>? _members;
  String? _error;
  String? _memberId;
  // null = all of the member's courts.
  String? _courtId;
  bool _weekView = true;
  DateTime _anchor = _today();

  List<GuestBookingRow> _guestBookings = const [];
  MembershipDetail? _detail;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get _facilityIdOrEmpty => ref.read(sessionControllerProvider).facility?.id ?? '';

  MemberScheduleSummary? get _member => _members?.where((m) => m.memberId == _memberId).firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fid = _facilityIdOrEmpty;
    if (fid.isEmpty) return;
    setState(() => _error = null);
    try {
      final rows = await ref.read(membershipRepositoryProvider).listMemberSchedules(fid);
      final members = groupMemberSchedules(rows);
      if (!mounted) return;
      setState(() {
        _members = members;
        _memberId ??= members.firstOrNull?.memberId;
        _courtId = _member?.courts.firstOrNull?.id;
      });
      await _loadAround();
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _members = const [];
        });
      }
    }
  }

  /// The member's plan details, and the guest bookings on their court(s) for the visible days.
  Future<void> _loadAround() async {
    final m = _member;
    final fid = _facilityIdOrEmpty;
    if (m == null || fid.isEmpty) return;
    final days = _days;
    final from = DateFormat('yyyy-MM-dd').format(days.first);
    final to = DateFormat('yyyy-MM-dd').format(days.last);
    final courtIds = _courtId != null ? [_courtId!] : m.courts.map((c) => c.id).toList();
    try {
      final bookingRepo = ref.read(bookingRepositoryProvider);
      final results = await Future.wait([
        for (final id in courtIds) bookingRepo.listGuestBookings(fid, courtId: id, from: from, to: to, limit: 200),
      ]);
      final detail = m.membershipId == null ? null : await ref.read(membershipRepositoryProvider).getMembershipDetail(m.membershipId!);
      if (!mounted || _memberId != m.memberId) return;
      setState(() {
        _guestBookings = [for (final r in results) ...r.rows].where((b) => b.status != 'cancelled').toList();
        _detail = detail;
      });
    } on AppException {
      // The member's own slots still show; the overlay and plan details just stay empty.
      if (mounted) setState(() => _guestBookings = const []);
    }
  }

  /// The days drawn: Monday–Sunday of the anchor's week, or just the anchor.
  List<DateTime> get _days {
    if (!_weekView) return [_anchor];
    final monday = _anchor.subtract(Duration(days: (_anchor.weekday + 6) % 7));
    return [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
  }

  void _shift(int direction) {
    setState(() => _anchor = _anchor.add(Duration(days: (_weekView ? 7 : 1) * direction)));
    _loadAround();
  }

  Future<void> _pickMember() async {
    final members = _members ?? const [];
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _memberId ?? '',
      options: [for (final m in members) (value: m.memberId, label: '${m.fullName} · ${m.phone}')],
    );
    if (picked == null || picked == _memberId) return;
    setState(() {
      _memberId = picked;
      _courtId = _member?.courts.firstOrNull?.id;
      _detail = null;
      _guestBookings = const [];
    });
    _loadAround();
  }

  Future<void> _pickCourt() async {
    final m = _member;
    if (m == null) return;
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _courtId ?? 'ALL',
      options: [(value: 'ALL', label: 'All Courts'), for (final c in m.courts) (value: c.id, label: c.name)],
    );
    if (picked == null) return;
    setState(() => _courtId = picked == 'ALL' ? null : picked);
    _loadAround();
  }

  @override
  Widget build(BuildContext context) {
    final m = _member;

    return Scaffold(
      appBar: AppBar(title: const Text('Membership Schedule')),
      body: SafeArea(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _members == null
                ? const _ScheduleSkeleton()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        Text(
                          "View a member's court schedule across the week, alongside guest bookings on the same court.",
                          style: AppTypography.secondary(context),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (m == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            child: Text(
                              'No members have a dedicated court schedule yet.',
                              textAlign: TextAlign.center,
                              style: AppTypography.secondary(context),
                            ),
                          )
                        else ...[
                          _memberPicker(m),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              PickerChip(label: _courtId == null ? 'All Courts' : (m.courts.where((c) => c.id == _courtId).firstOrNull?.name ?? 'Court'), onSelect: _pickCourt),
                              ChoiceChip(
                                label: const Text('Week'),
                                selected: _weekView,
                                onSelected: (_) {
                                  setState(() => _weekView = true);
                                  _loadAround();
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Day'),
                                selected: !_weekView,
                                onSelected: (_) {
                                  setState(() => _weekView = false);
                                  _loadAround();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _rangeBar(),
                          const SizedBox(height: AppSpacing.xs),
                          _legend(),
                          const SizedBox(height: AppSpacing.sm),
                          for (final day in _days) _dayCard(m, day),
                          const SizedBox(height: AppSpacing.md),
                          _detailsCard(m),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _memberPicker(MemberScheduleSummary m) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: _pickMember,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              AppAvatar(name: m.fullName),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select member', style: AppTypography.caption(context)),
                    Text(m.fullName, style: AppTypography.rowTitle(context)),
                    Text(m.phone, style: AppTypography.caption(context)),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeBar() {
    final days = _days;
    final fmt = DateFormat('d MMM yyyy');
    final label = days.length == 1 ? fmt.format(days.first) : '${fmt.format(days.first)} – ${fmt.format(days.last)}';
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1), tooltip: _weekView ? 'Previous week' : 'Previous day'),
        Expanded(
          child: Column(
            children: [
              Text(_weekView ? 'Weekly Schedule' : 'Daily Schedule', style: AppTypography.rowTitle(context)),
              Text(label, style: AppTypography.caption(context)),
            ],
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1), tooltip: _weekView ? 'Next week' : 'Next day'),
      ],
    );
  }

  Widget _legend() {
    final t = context.tokens;
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: AppTypography.caption(context)),
          ],
        );
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: 2,
      children: [dot(t.primary, 'Member slot'), dot(t.electricBlue, 'Guest booking')],
    );
  }

  Widget _dayCard(MemberScheduleSummary m, DateTime day) {
    final t = context.tokens;
    final isToday = day == _today();
    final slots = m.slots.where((s) => s.occursOn(day) && (_courtId == null || s.courtId == _courtId)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final guests = _guestBookings
        .where((b) => DateUtils.isSameDay(b.startTime, day))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEE, d MMM').format(day),
                    style: AppTypography.rowTitle(context).copyWith(color: isToday ? t.primary : null),
                  ),
                ),
                if (isToday) const StatusBadge(label: 'Today', tone: StatusTone.success),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (slots.isEmpty && guests.isEmpty)
              Text('No slots', style: AppTypography.caption(context))
            else ...[
              for (final s in slots)
                _entry(t.primary, '${s.startTime} – ${s.endTime}', '${s.batchName.isEmpty ? 'Member slot' : s.batchName} · ${s.courtName}'),
              for (final g in guests)
                _entry(
                  t.electricBlue,
                  '${DateFormat('HH:mm').format(g.startTime)} – ${DateFormat('HH:mm').format(g.endTime)}',
                  'Guest booking · ${g.guestName} · ${g.courtName}',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entry(Color color, String time, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(width: 4, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: AppTypography.rowTitle(context)),
                  Text(label, style: AppTypography.caption(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _detailsCard(MemberScheduleSummary m) {
    final detail = _detail;
    String kv(String? v) => (v == null || v.isEmpty) ? '—' : v;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: Text(k, style: AppTypography.caption(context))),
              Expanded(child: Text(v, style: AppTypography.body(context))),
            ],
          ),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: m.fullName),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.fullName, style: AppTypography.rowTitle(context)),
                    Text(
                      [m.phone, detail?.member.email].whereType<String>().where((s) => s.isNotEmpty).join(' | '),
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
              ),
              StatusBadge(label: m.isActive ? 'Active' : 'Inactive', tone: m.isActive ? StatusTone.success : StatusTone.neutral),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          row('Membership plan', kv(detail?.membership.name)),
          row('Valid till', detail == null ? '—' : DateFormat('d MMM yyyy').format(detail.membership.endDate)),
          row('Assigned courts', kv(m.courts.map((c) => c.name).join(', '))),
          row('Preferred time', kv(m.preferredTime)),
          if (m.membershipId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(AppPageRoute(builder: (_) => MembershipDetailScreen(membershipId: m.membershipId!))),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('View membership & history'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleSkeleton extends StatelessWidget {
  const _ScheduleSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        SkeletonListRow(),
        SizedBox(height: AppSpacing.md),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}
