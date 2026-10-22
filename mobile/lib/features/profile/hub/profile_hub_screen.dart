import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/profile_hub.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../authentication/auth_widgets.dart';
import '../../authentication/session_controller.dart';
import 'hub_providers.dart';
import 'hub_widgets.dart';

/// Profile hub — opened from the facility card at the top of Profile. Mirrors the web Profile page: who you are, your
/// GameAll plan, how the facility is doing this month, and the doors into everything else.
class ProfileHubScreen extends ConsumerWidget {
  const ProfileHubScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(hubProfileProvider);
    ref.invalidate(hubPlanProvider);
    ref.invalidate(hubStatsProvider);
    await ref.read(hubProfileProvider.future);
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final facilityName = ref.read(sessionControllerProvider).facility?.name ?? 'your facility';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of GameAll?'),
        content: Text("You'll be signed out of $facilityName on this device. You can sign back in any time."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.tokens.destructive),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final facility = ref.watch(sessionControllerProvider).facility;
    final profile = ref.watch(hubProfileProvider);
    final plan = ref.watch(hubPlanProvider);
    final stats = ref.watch(hubStatsProvider);

    return HubPage(
      title: 'Profile',
      onRefresh: () => _refresh(ref),
      children: [
        Text('Manage your account, facility information and preferences',
            style: TextStyle(fontSize: 13, color: t.textSecondary)),
        const SizedBox(height: AppSpacing.md),
        HubAsync<HubProfile>(
          value: profile,
          skeletonHeight: 230,
          onRetry: () => ref.invalidate(hubProfileProvider),
          builder: (p) => _Hero(profile: p, facilityPhone: facility?.businessPhone),
        ),
        const SizedBox(height: AppSpacing.lg),
        HubAsync<FacilityPlan>(
          value: plan,
          skeletonHeight: 190,
          onRetry: () => ref.invalidate(hubPlanProvider),
          builder: (p) => _PlanCard(plan: p, facilityName: facility?.name ?? 'Your facility'),
        ),
        const SizedBox(height: AppSpacing.lg),
        stats.when(
          loading: () => const _StatsSkeleton(),
          error: (_, _) => HubCard(
            child: Text('Your facility numbers are unavailable right now.', style: TextStyle(color: t.textSecondary)),
          ),
          data: (s) => _StatsGrid(stats: s),
        ),
        const SizedBox(height: AppSpacing.lg),
        _OptionCard(
          icon: Icons.person_rounded,
          title: 'Personal Information',
          subtitle: 'View and manage your personal details, contact information and profile photo.',
          onTap: () => context.push(AppRoutes.profilePersonal),
        ),
        _OptionCard(
          icon: Icons.apartment_rounded,
          title: 'Manage Facility Details',
          subtitle: 'View and manage your facility details, courts, sports, timings, pricing and more.',
          onTap: () => context.push(AppRoutes.profileManageFacility),
        ),
        _OptionCard(
          icon: Icons.credit_card_rounded,
          title: 'Payment Methods',
          subtitle: 'Manage your bank accounts and payment methods to receive payouts.',
          onTap: () => context.push(AppRoutes.profilePayouts),
        ),
        _OptionCard(
          icon: Icons.headset_mic_outlined,
          title: 'Help & Support',
          subtitle: 'Get help, raise a support ticket or view FAQs.',
          onTap: () => context.push(AppRoutes.profileSupport),
        ),
        _OptionCard(
          icon: Icons.settings_rounded,
          title: 'Settings',
          subtitle: 'Manage your notification preferences, security and other settings.',
          onTap: () => context.push(AppRoutes.profileSettings),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _confirmLogout(context, ref),
          icon: Icon(Icons.logout_rounded, color: t.destructive, size: 18),
          label: Text('Log out', style: TextStyle(color: t.destructive, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            side: BorderSide(color: t.destructive.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }
}

// ── Hero ───────────────────────────────────────────────────────────────────

/// Photo, name, verified badge, role, mobile and email laid over the profile artwork. The artwork is light in its middle
/// and dark in its corners in both themes, so the text on it is fixed rather than following the theme.
class _Hero extends ConsumerStatefulWidget {
  const _Hero({required this.profile, required this.facilityPhone});

  final HubProfile profile;
  final String? facilityPhone;

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  bool _uploading = false;
  String? _photoError;

  static const _ink = Color(0xFF1E293B);
  static const _inkMuted = Color(0xFF475569);

  Future<void> _pickPhoto() async {
    setState(() => _photoError = null);
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (file == null) return;
    final lower = file.name.toLowerCase();
    final type = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
                ? 'image/jpeg'
                : null;
    if (type == null) {
      setState(() => _photoError = 'Use a PNG, JPG or WebP image.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      setState(() => _photoError = 'Photos must be smaller than 2MB.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final repo = ref.read(profileHubRepositoryProvider);
      final url = await repo.uploadAvatar(bytes, file.name, type);
      await repo.updateProfile(
        fullName: widget.profile.fullName,
        phone: widget.profile.phone,
        avatarUrl: url,
        setAvatar: true,
      );
      ref.invalidate(hubProfileProvider);
    } on AppException catch (e) {
      if (mounted) setState(() => _photoError = e.message);
    } catch (_) {
      if (mounted) setState(() => _photoError = 'Could not upload this photo.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _edit(String? mobile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(profile: widget.profile, phone: mobile),
    );
    if (saved == true) ref.invalidate(hubProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = widget.profile;
    // Until a personal number is added, the facility's own contact number stands in for it.
    final mobile = (p.phone?.trim().isNotEmpty ?? false) ? p.phone : widget.facilityPhone;
    final initials = p.fullName.trim().isEmpty
        ? '?'
        : p.fullName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4FF),
          border: Border.all(color: t.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          image: const DecorationImage(image: AssetImage('assets/images/profile_banner.png'), fit: BoxFit.cover),
        ),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 56, AppSpacing.lg, AppSpacing.xl),
              child: Column(
                children: [
                  Center(child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.primary,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))],
                          image: (p.avatarUrl?.isNotEmpty ?? false)
                              ? DecorationImage(image: NetworkImage(p.avatarUrl!), fit: BoxFit.cover)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: (p.avatarUrl?.isNotEmpty ?? false)
                            ? null
                            : Text(initials, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: t.onPrimary)),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Material(
                          color: _ink,
                          shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploading ? null : _pickPhoto,
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: _uploading
                                  ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.photo_camera_outlined, size: 17, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )),
                  if (_photoError != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(_photoError!, style: TextStyle(fontSize: 12, color: t.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                    alignment: WrapAlignment.center,
                    runAlignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: 6,
                    children: [
                      Text(p.fullName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
                      const _VerifiedBadge(),
                    ],
                  ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: Text(p.roleTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _inkMuted)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ContactLine(
                    icon: Icons.phone_outlined,
                    text: (mobile?.trim().isNotEmpty ?? false) ? _formatPhone(mobile!) : 'Add your mobile number',
                    muted: !(mobile?.trim().isNotEmpty ?? false),
                  ),
                  const SizedBox(height: 6),
                  _ContactLine(icon: Icons.mail_outline_rounded, text: p.email),
                ],
              ),
              ),
            ),
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: () => _edit(mobile),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 15, color: _ink),
                        SizedBox(width: 6),
                        Text('Edit Profile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+91 98765 43210" for a stored 10-digit number; anything else is shown as stored.
String _formatPhone(String phone) {
  final n = phone.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?91(?=\d{10}$)'), '');
  return RegExp(r'^\d{10}$').hasMatch(n) ? '+91 ${n.substring(0, 5)} ${n.substring(5)}' : phone;
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 15, color: Color(0xFF047857)),
          SizedBox(width: 4),
          Text('Verified User', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF047857))),
        ],
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: muted ? const Color(0xFF64748B) : const Color(0xFF1E293B)),
          ),
        ),
      ],
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile, required this.phone});

  final HubProfile profile;
  final String? phone;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(
    text: (widget.phone ?? '').replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?91(?=\d{10}$)'), ''),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileHubRepositoryProvider).updateProfile(
            fullName: _name.text,
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your profile. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(color: t.surface0, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg2),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.textPrimary)),
                const SizedBox(height: 2),
                Text("Your email is your sign-in, so it can't be changed here.",
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Full name',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => (v == null || v.isEmpty || RegExp(r'^[6-9]\d{9}$').hasMatch(v)) ? null : 'Enter a valid 10-digit mobile number.',
                  decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  '),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, style: TextStyle(color: t.destructive, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.xl),
                AuthGradientButton(label: 'Save changes', loadingLabel: 'Saving…', isLoading: _saving, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Plan ───────────────────────────────────────────────────────────────────

/// "Active Membership Plan": GameAll's own plan for this facility — what the owner pays GameAll and until when. Past its
/// valid-till date, or once cancelled, the plan reads Inactive.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.facilityName});

  final FacilityPlan plan;
  final String facilityName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = plan.isActive();
    final left = plan.daysLeft();
    final accent = active ? t.primary : t.textSecondary;
    final interval = plan.interval;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: active ? t.accentFill(t.primary) : t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: active ? t.accentEdge(t.primary) : t.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: active ? t.primary : t.surface2, shape: BoxShape.circle),
                child: Icon(Icons.workspace_premium_rounded, size: 26, color: active ? t.onPrimary : t.textSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(active ? 'Active Membership Plan' : 'Membership Plan',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
                    Text(plan.planName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: t.textPrimary)),
                    Text('GameAll Club Management', style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
                  ],
                ),
              ),
              _StatusPill(active: active),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: t.borderColor),
          const SizedBox(height: AppSpacing.md),
          _PlanFact(icon: Icons.apartment_outlined, label: 'Facility', value: facilityName),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PlanFact(icon: Icons.currency_rupee_rounded, label: 'Plan Price', value: '${hubMoney(plan.priceMinor)} / $interval'),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PlanFact(icon: Icons.event_outlined, label: 'Valid Till', value: hubDate(DateTime.tryParse(plan.validTill))),
              ),
            ],
          ),
          if (active && left <= 14) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Your plan ends ${left == 0 ? 'today' : 'in $left day${left == 1 ? '' : 's'}'}. Contact GameAll to renew it.',
                style: TextStyle(fontSize: 12.5, color: t.warning)),
          ],
          if (!active) ...[
            const SizedBox(height: AppSpacing.md),
            Text('This plan has ${plan.status == 'cancelled' ? 'been cancelled' : 'expired'}. Contact GameAll to renew it.',
                style: TextStyle(fontSize: 12.5, color: t.destructive)),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _showDetails(context),
              child: const Text('View Plan Details'),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final t = context.tokens;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.planName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.textPrimary)),
              const SizedBox(height: 2),
              Text('${hubMoney(plan.priceMinor)} per ${plan.interval} · valid till ${hubDate(DateTime.tryParse(plan.validTill))}',
                  style: TextStyle(fontSize: 13, color: t.textSecondary)),
              const SizedBox(height: AppSpacing.lg),
              if (plan.features.isEmpty)
                Text("The details of this plan haven't been added yet.", style: TextStyle(color: t.textSecondary))
              else
                for (final f in plan.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_rounded, size: 18, color: t.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(f, style: TextStyle(fontSize: 14, color: t.textPrimary, height: 1.35))),
                      ],
                    ),
                  ),
              const SizedBox(height: AppSpacing.sm),
              Text('GameAll charges a flat membership fee — never a commission on your bookings or payments.',
                  style: TextStyle(fontSize: 12, color: t.textSecondary, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = active ? t.success : t.destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(active ? 'Active' : 'Inactive', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

class _PlanFact extends StatelessWidget {
  const _PlanFact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(icon, size: 20, color: t.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: t.textSecondary)),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stats ──────────────────────────────────────────────────────────────────

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(children: [
          Expanded(child: AppSkeleton(height: 76, radius: AppRadius.lg)),
          SizedBox(width: AppSpacing.md),
          Expanded(child: AppSkeleton(height: 76, radius: AppRadius.lg)),
        ]),
        SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(child: AppSkeleton(height: 76, radius: AppRadius.lg)),
          SizedBox(width: AppSpacing.md),
          Expanded(child: AppSkeleton(height: 76, radius: AppRadius.lg)),
        ]),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final HubStats stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tiles = [
      _StatTile(icon: Icons.event_available_rounded, color: t.electricBlue, value: '${stats.bookingsThisMonth}', label: 'Total Bookings', hint: 'This Month'),
      _StatTile(icon: Icons.groups_rounded, color: t.electricBlue, value: '${stats.activeMembers}', label: 'Active Members'),
      _StatTile(icon: Icons.grid_view_rounded, color: t.warning, value: '${stats.courts}', label: 'Courts / Turfs'),
      _StatTile(icon: Icons.currency_rupee_rounded, color: t.success, value: hubMoney(stats.revenueThisMonthMinor), label: 'Total Revenue', hint: 'This Month', round: true),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - AppSpacing.md) / 2;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [for (final tile in tiles) SizedBox(width: w, child: tile)],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.color, required this.value, required this.label, this.hint, this.round = false});

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? hint;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: round ? color : color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(round ? 40 : AppRadius.md),
            ),
            child: Icon(icon, size: 20, color: round ? Colors.white : color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: t.textPrimary)),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
                if (hint != null) Text(hint!, style: TextStyle(fontSize: 10.5, color: t.textSecondary.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Option cards ───────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: t.borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon: icon, color: t.electricBlue, size: 48),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.textPrimary)),
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: t.textSecondary, height: 1.4)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 4),
                  child: Icon(Icons.chevron_right_rounded, color: t.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
