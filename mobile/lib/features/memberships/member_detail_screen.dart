import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/page_transitions.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import 'create_membership_screen.dart';
import 'slot_format.dart';

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Premium read view for one member's membership — everything captured at
/// sign-up, their payment state, and the reserved session slot.
class MemberDetailScreen extends ConsumerStatefulWidget {
  const MemberDetailScreen({super.key, required this.membershipId});

  final String membershipId;

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  bool _loading = true;
  String? _error;
  MembershipDetail? _d;
  bool _recording = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _d == null;
      _error = null;
    });
    try {
      final d = await ref
          .read(membershipRepositoryProvider)
          .getMembershipDetail(widget.membershipId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _recordPayment() async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
              child: Text('Record payment',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            for (final m in const ['cash', 'upi', 'card', 'bank transfer'])
              ListTile(
                title: Text(m[0].toUpperCase() + m.substring(1)),
                onTap: () => Navigator.pop(sheet, m),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (method == null) return;
    setState(() => _recording = true);
    try {
      await ref
          .read(membershipRepositoryProvider)
          .recordMembershipPayment(widget.membershipId, method: method);
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Payment recorded')));
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _delete(String memberId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this member?'),
        content: Text(
            '$name and this membership will be removed. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: context.tokens.destructive),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(membershipRepositoryProvider).deleteMember(memberId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Member deleted')));
        Navigator.of(context).pop(true);
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) =>
            CreateMembershipScreen(membershipId: widget.membershipId),
      ),
    );
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final d = _d;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title:
              const Text('Member', style: TextStyle(fontWeight: FontWeight.w800)),
          leading: BackButton(
              onPressed: () => Navigator.of(context).pop(_changed)),
          actions: [
            if (d != null)
              IconButton(
                tooltip: 'Delete member',
                icon: Icon(Icons.delete_outline, color: tokens.destructive),
                onPressed: () => _delete(d.member.id, d.member.fullName),
              ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const _MemberDetailSkeleton()
              : _error != null || d == null
                  ? ErrorView(message: _error ?? 'Not found', onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                            AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                        children: [
                          _hero(d),
                          const SizedBox(height: AppSpacing.md),
                          _contactCard(d),
                          const SizedBox(height: AppSpacing.md),
                          _membershipCard(d),
                          const SizedBox(height: AppSpacing.md),
                          _paymentCard(d),
                          if (d.slot != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _slotCard(d.slot!),
                          ],
                          if ((d.referralName ?? '').isNotEmpty ||
                              (d.discoverySource ?? '').isNotEmpty ||
                              (d.notes ?? '').isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            _extraCard(d),
                          ],
                        ],
                      ),
                    ),
        ),
        bottomNavigationBar: d == null
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.surface0,
                    border:
                        Border(top: BorderSide(color: tokens.borderColor)),
                  ),
                  child: AuthGradientButton(
                      label: 'Edit membership', onPressed: _edit),
                ),
              ),
      ),
    );
  }

  // ── pieces ──────────────────────────────────────────────────────────────

  ({String label, Color color}) _statusOf(MembershipListStatus s) {
    final t = context.tokens;
    return switch (s) {
      MembershipListStatus.active => (label: 'Active', color: t.primary),
      MembershipListStatus.paymentIncomplete =>
        (label: 'Unpaid', color: t.warning),
      MembershipListStatus.inactive =>
        (label: 'Inactive', color: t.textSecondary),
    };
  }

  Widget _hero(MembershipDetail d) {
    final tokens = context.tokens;
    final st = _statusOf(d.displayStatus);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.violet.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.violet.withValues(alpha: 0.26),
            tokens.violet.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Row(
        children: [
          AppAvatar(name: d.member.fullName, size: AppAvatarSize.large),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.member.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('+91 ${d.member.phone}',
                    style: TextStyle(
                        fontSize: 13, color: tokens.textSecondary)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: st.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(st.label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: st.color)),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> rows, {Widget? action}) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary)),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: tokens.borderColor.withValues(alpha: 0.6)),
            rows[i],
          ],
        ],
      ),
    );
  }

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
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _contactCard(MembershipDetail d) {
    final m = d.member;
    return _card('Contact', [
      _kv('Phone', '+91 ${m.phone}'),
      _kv('Email', (m.email ?? '').isEmpty ? '—' : m.email!),
      _kv('Address', (m.address ?? '').isEmpty ? '—' : m.address!),
      _kv('Date of birth',
          (m.dateOfBirth ?? '').isEmpty ? '—' : _fmtDob(m.dateOfBirth!)),
      _kv('Gender', (m.gender ?? '').isEmpty ? '—' : m.gender!),
      _kv('Member since', _date(m.memberSince)),
    ]);
  }

  Widget _membershipCard(MembershipDetail d) {
    final mm = d.membership;
    return _card('Membership', [
      _kv('Plan', mm.name),
      _kv('Type', _typeLabel(mm.membershipType)),
      _kv('Starts', _date(mm.startDate)),
      _kv('Renews', _date(mm.endDate)),
      _kv('Duration',
          mm.durationDays == null ? '—' : '${mm.durationDays} days'),
      if (mm.membershipType.toUpperCase() == 'FAMILY')
        _kv('Family size', '${mm.maxFamilyMembers}'),
    ]);
  }

  Widget _paymentCard(MembershipDetail d) {
    final tokens = context.tokens;
    final p = d.payment;
    final mm = d.membership;
    final unpaid = d.displayStatus == MembershipListStatus.paymentIncomplete;
    return _card(
      'Payment',
      [
        _kv('Membership fee', Formatters.currencyInr(mm.membershipFeeInr)),
        if (mm.registrationFeeInr > 0)
          _kv('Registration', Formatters.currencyInr(mm.registrationFeeInr)),
        if (mm.gstPercent > 0)
          _kv('GST', '${mm.gstPercent}%'),
        _kv('Total', Formatters.currencyInr(mm.totalAmountInr)),
        _kv('Status', unpaid ? 'Payment pending' : 'Paid'),
        if (p != null && (p.method ?? '').isNotEmpty)
          _kv('Method', p.method![0].toUpperCase() + p.method!.substring(1)),
        if (p?.paidAt != null) _kv('Paid on', _date(p!.paidAt!)),
        if (unpaid)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _recording ? null : _recordPayment,
                style:
                    FilledButton.styleFrom(backgroundColor: tokens.violet),
                icon: _recording
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Record payment'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _slotCard(MembershipSlot s) {
    return _card('Session slot', [
      _kv('Batch', s.name),
      if ((s.courtName ?? '').isNotEmpty) _kv('Court', s.courtName!),
      _kv('Days', formatSlot(s.daysOfWeek, s.startTime, s.endTime)),
    ]);
  }

  Widget _extraCard(MembershipDetail d) {
    return _card('Extra', [
      if ((d.referralName ?? '').isNotEmpty)
        _kv('Referred by', d.referralName!),
      if ((d.discoverySource ?? '').isNotEmpty)
        _kv('Found you via', d.discoverySource!),
      if ((d.notes ?? '').isNotEmpty) _kv('Notes', d.notes!),
      if ((d.createdByName ?? '').isNotEmpty)
        _kv('Registered by', d.createdByName!),
    ]);
  }

  // ── formatting ──────────────────────────────────────────────────────────

  static String _date(DateTime d) =>
      '${d.day} ${_monthShort[d.month - 1]} ${d.year}';

  static String _fmtDob(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.day} ${_monthShort[d.month - 1]} ${d.year}';
  }

  static String _typeLabel(String db) {
    switch (db.toUpperCase()) {
      case 'FAMILY':
        return 'Family';
      case 'CORPORATE':
        return 'Corporate';
      default:
        return 'Individual';
    }
  }
}

/// Structure-shaped placeholder for the member detail page — a hero card
/// (avatar + name + status pill) followed by a few key-value detail cards,
/// mirroring `_hero` and the stacked `_contactCard`/`_membershipCard`/
/// `_paymentCard`.
class _MemberDetailSkeleton extends StatelessWidget {
  const _MemberDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        SkeletonCard(
          child: Row(
            children: const [
              AppSkeleton(width: 56, height: 56, radius: 28),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 140, height: 17),
                    SizedBox(height: 6),
                    AppSkeleton(width: 100, height: 12),
                  ],
                ),
              ),
              AppSkeleton(width: 56, height: 20, radius: AppRadius.pill),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SkeletonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSkeleton(width: 100, height: 14),
                  const SizedBox(height: AppSpacing.sm),
                  for (var j = 0; j < 3; j++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: const [
                          AppSkeleton(width: 90, height: 11),
                          Spacer(),
                          AppSkeleton(width: 80, height: 11),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
