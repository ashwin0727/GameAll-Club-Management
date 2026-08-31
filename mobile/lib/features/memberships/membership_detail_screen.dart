import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'membership_list_presentation.dart';
import 'slot_format.dart';

/// The Membership Details screen — mirrors
/// src/features/memberships/components/membership-detail-page.tsx. Reached
/// by tapping a row on the Memberships list. One `get_membership_detail`
/// read; Edit / Cancel membership / Delete member act through the shared
/// RPCs.
class MembershipDetailScreen extends ConsumerStatefulWidget {
  const MembershipDetailScreen({super.key, required this.membershipId});

  final String membershipId;

  @override
  ConsumerState<MembershipDetailScreen> createState() => _MembershipDetailScreenState();
}

class _MembershipDetailScreenState extends ConsumerState<MembershipDetailScreen> {
  MembershipDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref.read(membershipRepositoryProvider).getMembershipDetail(widget.membershipId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String _money(int inr) => Formatters.currencyInr(inr);

  Future<void> _edit() async {
    final d = _detail;
    if (d == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditMemberSheet(
        memberId: d.member.id,
        initialName: d.member.fullName,
        initialPhone: d.member.phone,
        initialEmail: d.member.email ?? '',
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _confirm(String kind) async {
    final d = _detail;
    if (d == null) return;
    final isDelete = kind == 'delete';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDelete ? 'Delete member' : 'Cancel membership'),
        content: Text(
          isDelete
              ? 'Permanently remove ${d.member.fullName}. This only works when they have no bookings and no settled payments.'
              : 'End this membership now. The record is kept for history.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isDelete ? 'Delete' : 'Cancel Membership', style: TextStyle(color: context.tokens.destructive)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = ref.read(membershipRepositoryProvider);
      if (isDelete) {
        await repo.deleteMember(d.member.id);
        if (mounted) context.pop();
        return;
      }
      await repo.cancelMembership(d.membershipId);
      _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _shareLink() {
    final d = _detail;
    if (d == null) return;
    final base = AppConfig.webAppUrl.trim();
    if (base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Self-registration link is not configured for this build.')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: '${base.replaceAll(RegExp(r'/+$'), '')}/join/${d.facilityId}'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membership sign-up link copied')));
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Details'),
        actions: [
          if (d != null) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: _edit),
            PopupMenuButton<String>(
              onSelected: _confirm,
              itemBuilder: (context) => [
                if (d.displayStatus == MembershipListStatus.active && d.membership.rawStatus != 'cancelled')
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel membership')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete member', style: TextStyle(color: context.tokens.destructive)),
                ),
              ],
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _error != null || d == null
                ? ErrorView(message: _error ?? 'Membership not found.', onRetry: _load)
                : ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: _content(context, d)),
      ),
    );
  }

  List<Widget> _content(BuildContext context, MembershipDetail d) {
    final tokens = context.tokens;
    final m = d.membership;
    return [
      // Header
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 24, child: Text(_initials(d.member.fullName))),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.member.fullName, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      StatusBadge(
                        label: membershipListStatusLabel(d.displayStatus),
                        tone: membershipListStatusTone(d.displayStatus),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _muted(context, [
              d.member.phone,
              if (d.member.email != null) d.member.email!,
              if (d.member.dateOfBirth != null) 'DOB ${Formatters.dateShort(DateTime.parse(d.member.dateOfBirth!))}',
              if (d.member.address != null) d.member.address!,
            ].join('  ·  ')),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _stat(context, 'Membership Type', m.name),
                _stat(context, 'Member Since', Formatters.dateShort(d.member.memberSince)),
                _stat(context, 'Linked By', d.createdByName ?? 'Self registered'),
                _stat(context, 'Start Date', Formatters.dateShort(m.startDate)),
                _stat(context, 'Payment Status', (d.payment?.status ?? 'pending').toUpperCase()),
                _stat(context, m.autoRenew ? 'Next Payment' : 'Expiry', Formatters.dateShort(m.endDate)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // Membership Information
      _sectionCard(context, 'Membership Information', [
        _row(context, 'Membership Type', m.name),
        _row(context, 'Category', _titleCase(m.membershipType)),
        _row(context, 'Start Date', Formatters.dateShort(m.startDate)),
        _row(context, m.autoRenew ? 'Next Payment Date' : 'Expiry Date', Formatters.dateShort(m.endDate),
            danger: isPastDate(m.endDate)),
        if (m.durationDays != null) _row(context, 'Duration', '${m.durationDays} days'),
        if (m.membershipType == 'FAMILY') _row(context, 'Max. Members', '${m.maxFamilyMembers}'),
        if (d.slot != null)
          _row(
            context,
            'Time Slot',
            d.slot!.courtName == null
                ? formatSlot(d.slot!.daysOfWeek, d.slot!.startTime, d.slot!.endTime)
                : '${d.slot!.courtName} · ${formatSlot(d.slot!.daysOfWeek, d.slot!.startTime, d.slot!.endTime)}',
          ),
        if (m.description != null) ...[
          const Divider(height: AppSpacing.lg),
          Text('Description', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(m.description!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ]),
      const SizedBox(height: AppSpacing.md),

      // Charges & Payment
      _sectionCard(context, 'Charges & Payment', [
        _row(context, 'Membership Fee', _money(m.membershipFeeInr)),
        _row(context, 'Registration Fee', _money(m.registrationFeeInr)),
        _row(context, 'Sub Total', _money(m.membershipFeeInr + m.registrationFeeInr)),
        _row(context, 'GST (${m.gstPercent}%)', _money(m.gstAmountInr)),
        const Divider(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Amount', style: TextStyle(fontWeight: FontWeight.w700, color: tokens.success)),
            Text(_money(m.totalAmountInr), style: TextStyle(fontWeight: FontWeight.w700, color: tokens.success)),
          ],
        ),
        const Divider(height: AppSpacing.lg),
        _row(context, 'Payment Mode', d.payment?.method?.toUpperCase() ?? '—'),
        _row(context, 'Payment Date',
            d.payment == null ? '—' : Formatters.dateTimeShort(d.payment!.paidAt ?? d.payment!.createdAt)),
        if (d.payment?.transactionId != null) _row(context, 'Transaction ID', d.payment!.transactionId!),
        if (d.paymentReference != null) _row(context, 'Reference', d.paymentReference!),
        _row(context, 'Payment Status', (d.payment?.status ?? 'pending').toUpperCase()),
      ]),
      const SizedBox(height: AppSpacing.md),

      // Additional Information
      _sectionCard(context, 'Additional Information', [
        _row(context, 'Contact Number', d.member.phone),
        if (d.member.gender != null) _row(context, 'Gender', d.member.gender!),
        _row(context, 'How did you find us?', d.discoverySource ?? '—'),
        _row(context, 'Referral By', d.referralName ?? '—'),
        const Divider(height: AppSpacing.lg),
        Text('Notes', style: AppTypography.rowTitle(context)),
        const SizedBox(height: AppSpacing.xs),
        Text(d.notes ?? 'No notes added.', style: AppTypography.secondary(context)),
      ]),
      const SizedBox(height: AppSpacing.md),

      // Membership Link
      _sectionCard(context, 'Membership Link', [
        Text('Share this link with players so they can register on their own.', style: AppTypography.caption(context)),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(label: 'Copy sign-up link', onPressed: _shareLink),
      ]),
      const SizedBox(height: AppSpacing.md),

      // Activity Timeline
      _sectionCard(
        context,
        'Activity Timeline',
        d.timeline.isEmpty
            ? [Text('No activity recorded.', style: AppTypography.secondary(context))]
            : d.timeline
                .map((ev) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: CircleAvatar(radius: 3, backgroundColor: tokens.success),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Wrap(
                              spacing: AppSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(ev.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(ev.actor, style: AppTypography.caption(context)),
                                Text(Formatters.dateTimeShort(ev.at), style: AppTypography.caption(context)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
      ),
      const SizedBox(height: AppSpacing.xl),
      PrimaryButton(label: 'Create Membership', onPressed: () => context.push(AppRoutes.membershipsNew)),
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  static String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).take(2);
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  static String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  Widget _muted(BuildContext context, String text) =>
      Text(text, style: AppTypography.caption(context));

  Widget _stat(BuildContext context, String label, String value) => SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption(context)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Widget _sectionCard(BuildContext context, String title, List<Widget> children) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      );

  Widget _row(BuildContext context, String label, String value, {bool danger = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: AppTypography.secondary(context))),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: danger ? context.tokens.destructive : context.tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EditMemberSheet extends ConsumerStatefulWidget {
  const _EditMemberSheet({
    required this.memberId,
    required this.initialName,
    required this.initialPhone,
    required this.initialEmail,
  });

  final String memberId;
  final String initialName;
  final String initialPhone;
  final String initialEmail;

  @override
  ConsumerState<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<_EditMemberSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _phone = TextEditingController(text: widget.initialPhone);
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = Validators.name(_name.text);
    if (nameError != null) return setState(() => _error = nameError);
    final phoneError = Validators.phone(_phone.text);
    if (phoneError != null) return setState(() => _error = phoneError);
    if (_email.text.trim().isNotEmpty) {
      final emailError = Validators.email(_email.text);
      if (emailError != null) return setState(() => _error = emailError);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(membershipRepositoryProvider).updateMember(
            widget.memberId,
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Member', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', loadingLabel: 'Saving…', isLoading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}