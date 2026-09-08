import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../data/models/facility.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../authentication/session_controller.dart';

/// Profile & settings — the owner's home for everything that isn't day-to-day
/// operations: their identity, the facility's configuration, business setup,
/// app preferences and support. Backed by the real signed-in session; rows
/// without a destination yet flag "coming soon" rather than showing fake data.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int? _courts;
  int? _sports;
  int? _pricingRules;
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    try {
      final areas = await ref
          .read(playingAreaRepositoryProvider)
          .getPlayingAreas(facility.id);
      final sports = await ref
          .read(sportsRepositoryProvider)
          .getFacilitySports(facility.id);
      final plan =
          await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);
      if (!mounted) return;
      setState(() {
        _courts = areas.where((PlayingArea a) => !a.archived).length;
        _sports = sports.where((FacilitySport s) => s.enabled).length;
        _pricingRules = plan?.rules.length ?? 0;
      });
    } on AppException catch (_) {
      // Counts are decorative — the screen renders fine without them.
    }
  }

  void _soon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Coming soon')));
  }

  static String _modeLabel(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final themeLabel = _modeLabel(ref.watch(themeModeControllerProvider));
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final facility = session.facility;
    final paymentsLive = facility != null &&
        (facility.onboardingStep == OnboardingStep.completed);

    return Scaffold(
      backgroundColor: t.surface0,
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _HeaderCard(
              name: user?.fullName ?? 'Owner',
              phone: (facility?.businessPhone.isNotEmpty ?? false)
                  ? facility!.businessPhone
                  : (user?.email ?? ''),
              roleLabel: (user?.role ?? 'owner').isEmpty
                  ? 'Owner'
                  : _titleCase(user!.role),
              facilityName: facility?.name ?? 'Your facility',
              facilitySub: _facilitySub(facility),
              logoUrl: facility?.logoUrl,
              onFacilityTap: _soon,
            ),
            const SizedBox(height: AppSpacing.xl),

            _sectionLabel('Facility'),
            _GroupCard(children: [
              _NavRow(
                  icon: Icons.storefront_outlined,
                  label: 'Facility details',
                  onTap: () => _facilityDetailsSheet(facility)),
              _NavRow(
                  icon: Icons.sports_tennis_outlined,
                  label: 'Sports & courts',
                  trailing: _courts == null ? null : '$_courts',
                  onTap: _soon),
              _NavRow(
                  icon: Icons.schedule_outlined,
                  label: 'Operating hours',
                  onTap: _soon),
              _NavRow(
                  icon: Icons.tune_rounded,
                  label: 'Pricing rules',
                  trailing:
                      _pricingRules == null ? null : '$_pricingRules active',
                  onTap: _soon),
              _NavRow(
                  icon: Icons.link_rounded,
                  label: 'Public booking & join links',
                  onTap: () => _joinLinkSheet(facility)),
            ]),
            const SizedBox(height: AppSpacing.xl),

            _sectionLabel('Business'),
            _GroupCard(children: [
              _NavRow(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Payments & payouts',
                trailing: paymentsLive ? 'Live' : 'Set up',
                trailingTone: paymentsLive ? t.primary : t.warning,
                trailingDot: paymentsLive,
                onTap: _soon,
              ),
              _NavRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Invoices & tax',
                  onTap: _soon),
              _NavRow(
                  icon: Icons.category_outlined,
                  label: 'Expense categories',
                  onTap: () => context.push(AppRoutes.financeExpenses)),
            ]),
            const SizedBox(height: AppSpacing.xl),

            _sectionLabel('App'),
            _GroupCard(children: [
              _ToggleRow(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                value: _notifications,
                onChanged: (v) => setState(() => _notifications = v),
              ),
              _NavRow(
                  icon: Icons.contrast_rounded,
                  label: 'Appearance',
                  trailing: themeLabel,
                  onTap: _appearanceSheet),
              _NavRow(
                  icon: Icons.language_rounded,
                  label: 'Language',
                  trailing: 'English',
                  onTap: _soon),
            ]),
            const SizedBox(height: AppSpacing.xl),

            _sectionLabel('Support'),
            _GroupCard(children: [
              _NavRow(
                  icon: Icons.help_outline_rounded,
                  label: 'Help centre',
                  onTap: _soon),
              _NavRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Contact us',
                  onTap: _contact),
              _NavRow(
                  icon: Icons.star_outline_rounded,
                  label: "What's new",
                  onTap: _soon),
            ]),
            const SizedBox(height: AppSpacing.xxl),

            _SignOutButton(
                onTap: () =>
                    ref.read(sessionControllerProvider.notifier).signOut()),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.more),
    );
  }

  String _facilitySub(Facility? f) {
    if (f == null) return '';
    final bits = <String>[];
    if (_courts != null) bits.add('$_courts court${_courts == 1 ? '' : 's'}');
    if (_sports != null) bits.add('$_sports sport${_sports == 1 ? '' : 's'}');
    if (f.address.city.isNotEmpty) bits.add(f.address.city);
    return bits.join('  ·  ');
  }

  Future<void> _appearanceSheet() async {
    final t = context.tokens;
    final current = ref.read(themeModeControllerProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Appearance',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              for (final m in const [
                (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
                (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
              ])
                InkWell(
                  onTap: () {
                    ref
                        .read(themeModeControllerProvider.notifier)
                        .setMode(m.$1);
                    Navigator.pop(sheet);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(m.$3,
                            size: 20,
                            color: current == m.$1
                                ? t.primary
                                : t.textSecondary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                            child: Text(m.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                        if (current == m.$1)
                          Icon(Icons.check_rounded,
                              size: 20, color: t.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _facilityDetailsSheet(Facility? f) async {
    if (f == null) return _soon();
    final t = context.tokens;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Facility details',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              _detailRow('Name', f.name),
              _detailRow('Phone',
                  f.businessPhone.isEmpty ? '—' : f.businessPhone),
              _detailRow('Email',
                  f.businessEmail.isEmpty ? '—' : f.businessEmail),
              _detailRow(
                  'Address',
                  [
                    f.address.line1,
                    f.address.area,
                    f.address.city,
                    f.address.state,
                    f.address.pinCode,
                  ].where((s) => s.isNotEmpty).join(', ')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String k, String v) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 78,
              child: Text(k,
                  style:
                      TextStyle(fontSize: 13, color: t.textSecondary))),
          Expanded(
            child: Text(v.isEmpty ? '—' : v,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _joinLinkSheet(Facility? f) async {
    final slug = f?.slug;
    final link = slug == null || slug.isEmpty
        ? 'https://gameall.in'
        : 'https://gameall.in/join/$slug';
    final t = context.tokens;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Public booking & join link',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Share this so players can book or join your facility.',
                  style:
                      TextStyle(fontSize: 12, color: t.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: t.borderColor),
                ),
                child: SelectableText(link,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        Navigator.pop(sheet);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheet);
                        launchUrl(Uri.parse(link),
                            mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _contact() async {
    final ok = await launchUrl(
        Uri.parse('mailto:support@gameall.in?subject=GameAll%20support'));
    if (!ok && mounted) _soon();
  }

  static String _titleCase(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.tokens.textSecondary)),
      );
}

// ─────────────────────────────────────────────────────── header card ──

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.phone,
    required this.roleLabel,
    required this.facilityName,
    required this.facilitySub,
    required this.logoUrl,
    required this.onFacilityTap,
  });

  final String name;
  final String phone;
  final String roleLabel;
  final String facilityName;
  final String facilitySub;
  final String? logoUrl;
  final VoidCallback onFacilityTap;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.primary.withValues(alpha: 0.28)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.primary.withValues(alpha: 0.16),
            t.violet.withValues(alpha: 0.10),
            t.surface1.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.violet,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  image: (logoUrl != null && logoUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(logoUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: (logoUrl != null && logoUrl!.isNotEmpty)
                    ? null
                    : Text(_initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: t.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: t.primary.withValues(alpha: 0.5)),
                ),
                child: Text(roleLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: t.primary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Material(
            color: t.surface2,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onFacilityTap,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: t.borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(Icons.home_work_outlined,
                          size: 18, color: t.primary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(facilityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                          if (facilitySub.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(facilitySub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: t.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: t.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── rows ──

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
            height: 1,
            thickness: 1,
            indent: 52,
            color: t.borderColor.withValues(alpha: 0.6)));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.trailingTone,
    this.trailingDot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final Color? trailingTone;
  final bool trailingDot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) ...[
              if (trailingDot) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: trailingTone ?? t.primary,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
              ],
              Text(trailing!,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: trailingTone ?? t.textSecondary)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 20, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: t.primary,
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.destructive.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: t.destructive.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded, size: 18, color: t.destructive),
              const SizedBox(width: AppSpacing.sm),
              Text('Sign out',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: t.destructive)),
            ],
          ),
        ),
      ),
    );
  }
}
