import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_search_field.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../memberships/assign_membership_sheet.dart';
import '../memberships/membership_plans_sheet.dart';
import '../memberships/membership_status.dart';
import '../memberships/membership_status_presentation.dart';
import 'member_form_sheet.dart';
import 'member_profile_screen.dart';

const List<MembershipDisplayStatus?> _statusFilters = [
  null, // All
  MembershipDisplayStatus.active,
  MembershipDisplayStatus.expiringSoon,
  MembershipDisplayStatus.expired,
  MembershipDisplayStatus.cancelled,
  MembershipDisplayStatus.noMembership,
];

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String? _facilityId;
  bool _isLoading = true;
  String? _loadError;

  final _queryController = TextEditingController();
  String _query = '';
  MembershipDisplayStatus? _statusFilter;
  List<FacilityMemberRow> _members = [];
  bool _listLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _isLoading = false;
          _loadError = 'Complete your facility setup before managing members.';
        });
        return;
      }
      setState(() {
        _facilityId = facility.id;
        _isLoading = false;
      });
      await _refreshList();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _refreshList() async {
    if (_facilityId == null) return;
    setState(() => _listLoading = true);
    try {
      final results = await ref.read(membershipRepositoryProvider).searchFacilityMembers(_facilityId!, query: _query);
      if (mounted) {
        setState(() {
          _members = results;
          _listLoading = false;
        });
      }
    } on AppException catch (_) {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refreshList);
  }

  List<FacilityMemberRow> get _filtered {
    if (_statusFilter == null) return _members;
    return _members.where((m) => computeMembershipStatus(status: m.status, endDate: m.endDate) == _statusFilter).toList();
  }

  Future<void> _openAddMember() async {
    if (_facilityId == null) return;
    final result = await showModalBottomSheet<AddMemberResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddMemberSheet(facilityId: _facilityId!),
    );
    if (result == null) return;
    if (result.isExisting && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member already exists — assigning membership.')));
    }
    await _openAssignMembership(result.memberId, memberName: 'this member');
  }

  Future<void> _openAssignMembership(String memberId, {required String memberName}) async {
    if (_facilityId == null) return;
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AssignMembershipSheet(facilityId: _facilityId!, memberId: memberId, memberName: memberName),
    );
    if (assigned == true) _refreshList();
  }

  Future<void> _openPlans() async {
    if (_facilityId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipPlansSheet(facilityId: _facilityId!),
    );
  }

  Future<void> _openProfile(FacilityMemberRow member) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => MemberProfileScreen(facilityId: _facilityId!, member: member)),
    );
    if (changed == true) _refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          if (_facilityId != null)
            IconButton(icon: const Icon(Icons.card_membership), tooltip: 'Membership Plans', onPressed: _openPlans),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading members…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSearchField(
                      controller: _queryController,
                      hintText: 'Search by name, phone, or email',
                      onChanged: _onQueryChanged,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: AppSpacing.minTouchTarget,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _statusFilters.map((status) {
                          return Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.sm),
                            child: ChoiceChip(
                              label: Text(status == null ? 'All' : membershipDisplayStatusLabel(status)),
                              selected: _statusFilter == status,
                              onSelected: (_) => setState(() => _statusFilter = status),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_listLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_filtered.isEmpty)
                      EmptyStateView(
                        message: _members.isEmpty
                            ? 'No members yet — add your first member to start tracking memberships.'
                            : 'No members match your filters.',
                        actionLabel: _members.isEmpty ? '+ Add Member' : null,
                        onAction: _members.isEmpty ? _openAddMember : null,
                      )
                    else
                      ..._filtered.map((m) {
                        final status = computeMembershipStatus(status: m.status, endDate: m.endDate);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: InkWell(
                            onTap: () => _openProfile(m),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            child: AppCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.fullName, style: AppTypography.rowTitle(context)),
                                        Text(m.phone, style: AppTypography.caption(context)),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          m.planName != null && m.endDate != null
                                              ? '${m.planName} · Expires ${Formatters.dateShort(m.endDate!)}'
                                              : '—',
                                          style: AppTypography.secondary(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusBadge(label: membershipDisplayStatusLabel(status), tone: membershipDisplayStatusTone(status)),
                                  const SizedBox(width: AppSpacing.sm),
                                  const Icon(Icons.chevron_right, color: AppColors.muted),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
      floatingActionButton: _facilityId == null
          ? null
          : FloatingActionButton.extended(onPressed: _openAddMember, icon: const Icon(Icons.add), label: const Text('Add Member')),
    );
  }
}