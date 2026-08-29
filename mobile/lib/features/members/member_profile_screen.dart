import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/booking.dart';
import '../../data/models/membership.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../bookings/booking_status_presentation.dart';
import '../bookings/bookings_screen.dart';
import '../memberships/assign_membership_sheet.dart';
import '../memberships/cancel_membership_sheet.dart';
import '../memberships/membership_status.dart';
import '../memberships/membership_status_presentation.dart';
import 'member_form_sheet.dart';

/// Mirrors `member-profile-dialog.tsx`, adapted to a full mobile screen the
/// way `GuestProfileScreen` adapts the guest profile dialog.
class MemberProfileScreen extends ConsumerStatefulWidget {
  const MemberProfileScreen({super.key, required this.facilityId, required this.member});

  final String facilityId;
  final FacilityMemberRow member;

  @override
  ConsumerState<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends ConsumerState<MemberProfileScreen> {
  late FacilityMemberRow _member = widget.member;
  bool _isLoading = true;
  String? _loadError;
  MemberStats? _stats;
  List<Membership> _membershipHistory = [];
  List<Booking> _bookingHistory = [];
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final membershipRepo = ref.read(membershipRepositoryProvider);
      final stats = await membershipRepo.getMemberStats(_member.memberId, widget.facilityId);
      final history = await membershipRepo.getMembershipHistory(_member.memberId, widget.facilityId);
      final bookings = await membershipRepo.getMemberBookings(_member.memberId, widget.facilityId, limit: 20);
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(widget.facilityId);
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(widget.facilityId);
      setState(() {
        _stats = stats;
        _membershipHistory = history;
        _bookingHistory = bookings;
        _facilitySports = facilitySports.where((fs) => fs.enabled).toList();
        _sports = sports;
        _areas = areas.where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled).toList();
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _editMember() async {
    final saved = await showModalBottomSheet<FacilityMemberRow>(
      context: context,
      isScrollControlled: true,
      builder: (context) => EditMemberSheet(member: _member),
    );
    if (saved != null) {
      setState(() {
        _member = saved;
        _changed = true;
      });
    }
  }

  /// Membership activation on the Razorpay path is now entirely
  /// server-side (settle_payment → activate_membership,
  /// 0021_payment_settlement.sql), so [AssignMembershipSheet] no longer
  /// hands back a client-side [Membership] object to patch local state
  /// from — it only pops `true`/null. Refetch this member's row from the
  /// server instead of reconstructing it from a returned object, the same
  /// way [MembersScreen]'s list refresh does.
  Future<void> _renewMembership() async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AssignMembershipSheet(
        facilityId: widget.facilityId,
        memberId: _member.memberId,
        memberName: _member.fullName,
      ),
    );
    if (assigned == true) {
      await _reloadMemberRow();
      setState(() => _changed = true);
      _load();
    }
  }

  Future<void> _reloadMemberRow() async {
    try {
      final rows = await ref
          .read(membershipRepositoryProvider)
          .searchFacilityMembers(widget.facilityId, query: _member.phone);
      final matches = rows.where((m) => m.memberId == _member.memberId);
      if (matches.isNotEmpty && mounted) {
        setState(() => _member = matches.first);
      }
    } on AppException catch (_) {
      // Best-effort refresh — the sheet already reported success; a failed
      // refetch here just leaves the previously-displayed row stale until
      // the next visit, never a fabricated membership.
    }
  }

  /// Shown only when the member has an active membership — mirrors
  /// `member.membershipId && displayStatus === "ACTIVE"` in
  /// `member-profile-dialog.tsx` exactly (same condition, not "has ever had
  /// a membership").
  Future<void> _cancelMembership() async {
    final membershipId = _member.membershipId;
    if (membershipId == null) return;
    final cancelled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CancelMembershipSheet(
        membershipId: membershipId,
        planName: _member.planName ?? 'Membership',
      ),
    );
    if (cancelled == true) {
      setState(() => _changed = true);
      await _reloadMemberRow();
      _load();
    }
  }

  Future<void> _bookCourt() async {
    final booked = await showModalBottomSheet<Booking>(
      context: context,
      isScrollControlled: true,
      builder: (context) => QuickBookingSheet(
        facilityId: widget.facilityId,
        facilitySports: _facilitySports,
        sports: _sports,
        areas: _areas,
        initialMember: MemberSearchResult(id: _member.memberId, fullName: _member.fullName, phone: _member.phone, email: _member.email),
      ),
    );
    if (booked != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_member.fullName)),
        body: SafeArea(
          child: _isLoading
              ? const LoadingView(message: 'Loading member profile…')
              : _loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phone: ${_member.phone}', style: AppTypography.secondary(context)),
                      if (_member.email != null) Text('Email: ${_member.email}', style: AppTypography.secondary(context)),
                      const SizedBox(height: AppSpacing.md),
                      _buildCurrentMembership(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildStats(),
                      const SizedBox(height: AppSpacing.lg),
                      Text('Membership History', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (_membershipHistory.isEmpty)
                        Text('No membership history yet.', style: AppTypography.secondary(context))
                      else
                        ..._membershipHistory.map(_buildMembershipHistoryCard),
                      const SizedBox(height: AppSpacing.lg),
                      Text('Booking History', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (_bookingHistory.isEmpty)
                        EmptyStateView(message: 'No bookings found.', actionLabel: '+ Book Court', onAction: _bookCourt)
                      else
                        ..._bookingHistory.map(_buildBookingCard),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(child: SecondaryButton(label: 'Edit Member', onPressed: _editMember)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: SecondaryButton(
                              label: _member.membershipId != null ? 'Renew Membership' : 'Add Membership',
                              onPressed: _renewMembership,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      PrimaryButton(label: 'Book Court', onPressed: _bookCourt),
                      if (_member.membershipId != null &&
                          computeMembershipStatus(status: _member.status, endDate: _member.endDate) ==
                              MembershipDisplayStatus.active) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.destructive),
                            onPressed: _cancelMembership,
                            child: const Text('Cancel Membership'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCurrentMembership() {
    final status = computeMembershipStatus(status: _member.status, endDate: _member.endDate);
    if (_member.membershipId == null || _member.planName == null || _member.endDate == null) {
      return AppCard(
        child: Row(
          children: [
            Expanded(child: Text('No membership assigned yet.', style: AppTypography.secondary(context))),
            StatusBadge(label: membershipDisplayStatusLabel(status), tone: membershipDisplayStatusTone(status)),
          ],
        ),
      );
    }
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_member.planName!, style: Theme.of(context).textTheme.titleSmall),
                Text('Expires ${Formatters.dateShort(_member.endDate!)}', style: AppTypography.caption(context)),
              ],
            ),
          ),
          StatusBadge(label: membershipDisplayStatusLabel(status), tone: membershipDisplayStatusTone(status)),
        ],
      ),
    );
  }

  Widget _buildMembershipHistoryCard(Membership m) {
    final status = computeMembershipStatus(status: m.status, endDate: m.endDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.planName, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '${Formatters.dateShort(m.startDate)} – ${Formatters.dateShort(m.endDate)}',
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            StatusBadge(label: membershipDisplayStatusLabel(status), tone: membershipDisplayStatusTone(status)),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Booking b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Formatters.dateShort(b.startTime)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      StatusBadge(label: bookingStatusLabel(b.status), tone: bookingStatusTone(b.status)),
                      StatusBadge(label: paymentStatusLabel(b.paymentStatus), tone: paymentStatusTone(b.paymentStatus)),
                    ],
                  ),
                ],
              ),
            ),
            Text(b.amountMinor != null ? Formatters.currencyInr((b.amountMinor! / 100).round()) : '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Total Visits', value: '${stats.totalVisits}')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _StatTile(label: 'Total Amount', value: Formatters.currencyInr((stats.totalAmountMinor / 100).round()))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _StatTile(label: 'Pending', value: Formatters.currencyInr((stats.pendingAmountMinor / 100).round()))),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Last Visit: ${stats.lastVisit != null ? Formatters.dateShort(stats.lastVisit!) : 'Never'}',
          style: AppTypography.secondary(context),
        ),
        if (stats.sports.isNotEmpty)
          Text('Sports: ${stats.sports.map((s) => s.sportName).join(', ')}', style: AppTypography.secondary(context)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}