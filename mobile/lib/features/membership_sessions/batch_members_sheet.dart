import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/booking.dart';
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';

/// Assign/remove members eligible to book one batch's sessions. Mirrors
/// `batch-members-dialog.tsx`, searching via the existing
/// `MembershipRepository.searchMembers` (facility-scoped member search) —
/// no duplicate member-search logic here.
class BatchMembersSheet extends ConsumerStatefulWidget {
  const BatchMembersSheet({super.key, required this.facilityId, required this.batch});

  final String facilityId;
  final MembershipBatch batch;

  @override
  ConsumerState<BatchMembersSheet> createState() => _BatchMembersSheetState();
}

class _BatchMembersSheetState extends ConsumerState<BatchMembersSheet> {
  List<MembershipBatchMember>? _assigned;
  final Map<String, String> _memberNames = {};
  final _queryController = TextEditingController();
  List<MemberSearchResult> _results = [];
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final members = await ref.read(membershipSessionRepositoryProvider).getBatchMembers(widget.batch.id);
      if (!mounted) return;
      setState(() => _assigned = members);
      final missing = members.where((m) => !_memberNames.containsKey(m.memberId)).toList();
      if (missing.isNotEmpty) {
        final found = await ref
            .read(membershipRepositoryProvider)
            .searchFacilityMembers(widget.facilityId, limit: 200);
        if (!mounted) return;
        setState(() {
          for (final row in found) {
            _memberNames[row.memberId] = row.fullName;
          }
        });
      }
    } on AppException catch (_) {
      if (mounted) setState(() => _assigned = []);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await ref.read(membershipRepositoryProvider).searchMembers(widget.facilityId, value);
        if (mounted) setState(() => _results = results);
      } on AppException catch (_) {
        // Search errors stay silent — the field simply shows no results.
      }
    });
  }

  Future<void> _assign(MemberSearchResult member) async {
    setState(() => _error = null);
    try {
      await ref.read(membershipSessionRepositoryProvider).assignBatchMember(widget.batch.id, member.id);
      _memberNames[member.id] = member.fullName;
      _queryController.clear();
      if (mounted) setState(() => _results = []);
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remove(String memberId) async {
    try {
      await ref.read(membershipSessionRepositoryProvider).removeBatchMember(widget.batch.id, memberId);
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.batch.name} — Members', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Capacity ${widget.batch.capacity} · members eligible to book this batch\'s sessions.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_assigned == null)
                  const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
                else ...[
                  if (_assigned!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('No members assigned.'),
                    )
                  else
                    ..._assigned!.map(
                      (m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_memberNames[m.memberId] ?? m.memberId),
                        trailing: TextButton(onPressed: () => _remove(m.memberId), child: const Text('Remove')),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _queryController,
                    onChanged: _onQueryChanged,
                    decoration: const InputDecoration(labelText: 'Search members to assign', hintText: 'Name or phone'),
                  ),
                  if (_results.isNotEmpty)
                    ..._results.map(
                      (r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.fullName),
                        subtitle: Text(r.phone),
                        onTap: () => _assign(r),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}