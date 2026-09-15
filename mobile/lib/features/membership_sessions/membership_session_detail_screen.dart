import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership_session_dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import 'batch_members_sheet.dart';
import 'membership_sessions_screen.dart' show daysLabel;

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
  final Set<String> _removingMemberIds = {};

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
    setState(() => _removingMemberIds.add(memberId));
    try {
      await ref.read(membershipSessionRepositoryProvider).removeBatchMember(widget.batchId, memberId);
      await _load();
    } on AppException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _removingMemberIds.remove(memberId));
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
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session details',
            style: TextStyle(fontWeight: FontWeight.w800)),
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
                const PopupMenuItem(value: 'edit', child: Text('Edit session')),
                const PopupMenuItem(
                    value: 'release', child: Text('Release guest slots')),
                const PopupMenuItem(
                    value: 'block', child: Text("Block today's occurrence")),
                const PopupMenuItem(
                    value: 'duplicate', child: Text('Duplicate session')),
                PopupMenuItem(
                    value: 'toggle',
                    child: Text(d.isActive
                        ? 'Pause session'
                        : 'Activate session')),
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
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                      children: [
                        _hero(d!),
                        const SizedBox(height: AppSpacing.md),
                        _capacityCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _scheduleCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _membersCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _guestSlotsCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _notesCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _linkCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _sessionInfoCard(d),
                        const SizedBox(height: AppSpacing.md),
                        _activityCard(),
                      ],
                    ),
                  ),
      ),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(
                  color: tokens.surface0,
                  border:
                      Border(top: BorderSide(color: tokens.borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: tokens.surface2,
                        shape: StadiumBorder(
                            side: BorderSide(color: tokens.borderColor)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _openEdit,
                          child: Container(
                            height: 56,
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 16, color: tokens.textPrimary),
                                const SizedBox(width: AppSpacing.sm),
                                Text('Edit',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: tokens.textPrimary)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AuthGradientButton(
                        label: 'Release slots',
                        onPressed: _openReleaseGuestSlots,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ── shared bits ─────────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.tokens.borderColor),
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: context.tokens.textPrimary,
        ),
      );

  Widget _kv(String label, String value) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    final tokens = context.tokens;
    final onC = tokens.onAccent(tokens.violet);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onC.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: onC),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: onC)),
        ],
      ),
    );
  }

  // ── hero ────────────────────────────────────────────────────────────────

  Widget _hero(MembershipSessionDetail d) {
    final tokens = context.tokens;
    final onC = tokens.onAccent(tokens.violet);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: tokens.accentSolid(tokens.violet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: onC.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.event_repeat_rounded, color: onC, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: onC)),
                    const SizedBox(height: 2),
                    Text('${d.sportName} · ${d.courtName}',
                        style: TextStyle(
                            fontSize: 13,
                            color: onC.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              _statusPill(d.isActive),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _chip(Icons.schedule,
                  '${_t12(d.startTime)} – ${_t12(d.endTime)}'),
              _chip(Icons.calendar_today_rounded, daysLabel(d.daysOfWeek)),
              _chip(Icons.groups_outlined, '${d.capacity} seats'),
              if ((d.planName ?? '').isNotEmpty)
                _chip(Icons.card_membership, d.planName!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool active) {
    final tokens = context.tokens;
    final c = active ? tokens.primary : tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.check_circle : Icons.pause_circle_filled,
              size: 13, color: c),
          const SizedBox(width: 4),
          Text(active ? 'Active' : 'Paused',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }

  static String _t12(String hhmmStr) {
    final p = hhmmStr.split(':');
    if (p.length < 2) return hhmmStr;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return m == 0 ? '$h12 $period' : '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  // ── capacity ────────────────────────────────────────────────────────────

  Widget _capacityCard(MembershipSessionDetail d) {
    final tokens = context.tokens;
    final utilization =
        d.capacity > 0 ? ((d.rosterCount / d.capacity) * 100).round() : 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Capacity today'),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _CapacityDonut(
                capacity: d.capacity,
                members: d.rosterCount,
                guestsBooked: d.guestsBookedToday,
                availableToRelease: d.availableToRelease,
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  children: [
                    _statDot(tokens.primary, 'Members', d.rosterCount),
                    const SizedBox(height: AppSpacing.md),
                    _statDot(tokens.violet, 'Guests booked',
                        d.guestsBookedToday),
                    const SizedBox(height: AppSpacing.md),
                    _statDot(tokens.textSecondary.withValues(alpha: 0.5),
                        'Free to release', d.availableToRelease),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Utilization',
                  style:
                      TextStyle(fontSize: 13, color: tokens.textSecondary)),
              const Spacer(),
              Text('$utilization%',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: utilization.clamp(0, 100) / 100,
              minHeight: 7,
              backgroundColor: tokens.surface2,
              valueColor: AlwaysStoppedAnimation(tokens.violet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDot(Color color, String label, int value) {
    final tokens = context.tokens;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 13, color: tokens.textPrimary)),
        ),
        Text('$value',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  // ── schedule ────────────────────────────────────────────────────────────

  Widget _scheduleCard(MembershipSessionDetail d) {
    final next = d.nextOccurrenceDate != null
        ? Formatters.dateShort(d.nextOccurrenceDate!)
        : (d.runsToday ? 'Today' : '—');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Schedule'),
          const SizedBox(height: AppSpacing.sm),
          _kv('Days', daysLabel(d.daysOfWeek)),
          _dividerRow(),
          _kv('Time', '${_t12(d.startTime)} – ${_t12(d.endTime)}'),
          _dividerRow(),
          _kv('Duration', _durationLabel(d.startTime, d.endTime)),
          _dividerRow(),
          _kv('Recurrence', 'Every week'),
          _dividerRow(),
          _kv('Started', Formatters.dateShort(d.createdAt)),
          _dividerRow(),
          _kv('Ends', 'No expiry'),
          _dividerRow(),
          _kv('Next session', next),
        ],
      ),
    );
  }

  Widget _dividerRow() =>
      Divider(height: 1, color: context.tokens.borderColor.withValues(alpha: 0.6));

  // ── members ─────────────────────────────────────────────────────────────

  Widget _membersCard(MembershipSessionDetail d) {
    final tokens = context.tokens;
    final members = _members ?? const <MembershipSessionMemberRow>[];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: _sectionTitle(
                      'Members  ${members.length}/${d.capacity}')),
              TextButton.icon(
                onPressed:
                    members.length >= d.capacity ? null : _openAddMember,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(foregroundColor: tokens.violet),
              ),
            ],
          ),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('No members assigned yet.',
                  style: TextStyle(color: tokens.textSecondary)),
            )
          else
            for (var i = 0; i < members.length; i++) ...[
              if (i > 0) _dividerRow(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    AppAvatar(
                        name: members[i].fullName,
                        size: AppAvatarSize.small),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(members[i].fullName,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 1),
                          Text(
                            '${members[i].phone} · added ${Formatters.dateShort(members[i].addedOn)}',
                            style: TextStyle(
                                fontSize: 12, color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: _removingMemberIds.contains(members[i].memberId)
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.close,
                              size: 16, color: tokens.textSecondary),
                      tooltip: 'Remove from session',
                      onPressed: _removingMemberIds.contains(members[i].memberId)
                          ? null
                          : () => _removeMember(members[i].memberId),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  // ── guest slots ─────────────────────────────────────────────────────────

  Widget _guestSlotsCard(MembershipSessionDetail d) {
    final tokens = context.tokens;
    final availableToBook =
        math.max(0, d.releasedToday - d.guestsBookedToday);
    final tiles = <({String label, int value, bool highlight})>[
      (label: 'Capacity', value: d.capacity, highlight: false),
      (label: 'Released', value: d.releasedToday, highlight: false),
      (label: 'Booked', value: d.guestsBookedToday, highlight: false),
      (label: 'Open', value: availableToBook, highlight: true),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Guest slots today'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      color: tiles[i].highlight
                          ? tokens.accentSolid(tokens.primary)
                          : tokens.surface2,
                      border: tiles[i].highlight
                          ? null
                          : Border.all(color: tokens.borderColor),
                    ),
                    child: Column(
                      children: [
                        Text('${tiles[i].value}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: tiles[i].highlight
                                  ? tokens.onAccent(tokens.primary)
                                  : tokens.textPrimary,
                            )),
                        const SizedBox(height: 1),
                        Text(tiles[i].label,
                            style: TextStyle(
                                fontSize: 11,
                                color: tiles[i].highlight
                                    ? tokens.onAccent(tokens.primary)
                                        .withValues(alpha: 0.8)
                                    : tokens.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Released slots open for guest booking on a first-come basis.',
            style: TextStyle(fontSize: 12, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── notes ───────────────────────────────────────────────────────────────

  Widget _notesCard(MembershipSessionDetail d) {
    final tokens = context.tokens;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Notes')),
              TextButton.icon(
                onPressed: _editNotes,
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: tokens.violet),
              ),
            ],
          ),
          Text(
            (d.notes == null || d.notes!.isEmpty)
                ? 'No notes for this session yet.'
                : d.notes!,
            style: TextStyle(
                fontSize: 13, height: 1.4, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── link ────────────────────────────────────────────────────────────────

  Widget _linkCard(MembershipSessionDetail d) {
    final tokens = context.tokens;
    final link =
        'https://gameall.club/join/${d.facilityId}?session=${d.batchId}';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Registration link'),
          const SizedBox(height: 4),
          Text('Share so members can register for this session.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, 4, 4),
            decoration: BoxDecoration(
              color: tokens.surface2,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: tokens.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: tokens.textSecondary)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy_rounded,
                      size: 18, color: tokens.violet),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    _toast('Link copied');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── session info ────────────────────────────────────────────────────────

  Widget _sessionInfoCard(MembershipSessionDetail d) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Session info'),
          const SizedBox(height: AppSpacing.sm),
          _kv('Session ID', 'SES${d.batchId.substring(0, 3).toUpperCase()}'),
          _dividerRow(),
          _kv('Facility', d.facilityName ?? '—'),
          _dividerRow(),
          _kv('Address', d.facilityAddress ?? '—'),
          _dividerRow(),
          _kv('Type', 'Membership protected'),
          _dividerRow(),
          _kv('Guest release', 'Allowed'),
          _dividerRow(),
          _kv('Payment', 'Included in membership'),
          _dividerRow(),
          _kv('Created by', d.createdByName ?? '—'),
          _dividerRow(),
          _kv('Created', Formatters.dateTimeShort(d.createdAt)),
          _dividerRow(),
          _kv('Updated', Formatters.dateTimeShort(d.updatedAt)),
        ],
      ),
    );
  }

  // ── activity ────────────────────────────────────────────────────────────

  Widget _activityCard() {
    final tokens = context.tokens;
    final rows = _activity;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Activity'),
          const SizedBox(height: AppSpacing.md),
          if (rows == null)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Text('No activity yet.',
                style: TextStyle(color: tokens.textSecondary))
          else
            for (var i = 0; i < rows.length; i++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: tokens.violet, shape: BoxShape.circle),
                        ),
                        if (i != rows.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: tokens.borderColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rows[i].detail,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${rows[i].actor != null ? '${rows[i].actor} · ' : ''}${Formatters.dateTimeShort(rows[i].at)}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
    final tokens = context.tokens;
    return SizedBox(
      width: 118,
      height: 118,
      child: CustomPaint(
        painter: _DonutPainter(
          track: tokens.surface2,
          segments: [
            (members.toDouble(), tokens.primary),
            (guestsBooked.toDouble(), tokens.violet),
            (availableToRelease.toDouble(),
                tokens.textSecondary.withValues(alpha: 0.4)),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$capacity',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800)),
              Text('seats',
                  style: TextStyle(
                      fontSize: 11, color: tokens.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.track});

  final List<(double, Color)> segments;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.$1);
    final rect = Offset.zero & size;
    const stroke = 12.0;
    final arcRect = rect.deflate(stroke / 2);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, bg);
    if (total <= 0) return;
    var start = -math.pi / 2;
    const gap = 0.04;
    for (final seg in segments) {
      if (seg.$1 <= 0) continue;
      final sweep = (seg.$1 / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = seg.$2;
      canvas.drawArc(arcRect, start + gap, sweep - gap * 2, false, paint);
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