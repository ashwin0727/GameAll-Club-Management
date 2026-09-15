import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/facility.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';

/// Screen 6 of the redesigned onboarding — "You're open for business". By
/// the time we land here the Payments step has already run
/// `complete_facility_setup`; this screen confirms it, hands over the
/// booking link, and points at the obvious next actions.
class SetupSummaryScreen extends ConsumerStatefulWidget {
  const SetupSummaryScreen({super.key});

  @override
  ConsumerState<SetupSummaryScreen> createState() => _SetupSummaryScreenState();
}

class _SetupSummaryScreenState extends ConsumerState<SetupSummaryScreen> {
  bool _loading = true;
  String? _error;
  Facility? _facility;

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
      var facility = ref.read(sessionControllerProvider).facility ??
          await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      // Self-heal: if we somehow arrived without setup marked complete,
      // finish it (the RPC is idempotent).
      if (facility.onboardingStep != OnboardingStep.completed) {
        try {
          facility = await ref
              .read(onboardingRepositoryProvider)
              .completeSetup(facility.id);
          await ref.read(sessionControllerProvider.notifier).refresh();
        } catch (_) {
          /* best effort */
        }
      }
      setState(() {
        _facility = facility;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e, stack) {
      debugPrint('Setup complete load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We couldn’t load this step. Please try again.';
      });
    }
  }

  String get _bookingLink {
    final slug = _facility?.slug;
    return slug == null ? 'gameall.in' : 'gameall.in/$slug';
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: 'https://$_bookingLink'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Booking link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: Builder(
        builder: (context) {
          final tokens = context.tokens;
          return PopScope(
            canPop: false,
            // Setup is done — a system back from here goes to the dashboard,
            // never back into the wizard and never closing the app.
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) context.go(AppRoutes.dashboard);
            },
            child: Scaffold(
            body: AuthGradientBackground(
              child: SafeArea(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: tokens.textSecondary)),
                            ),
                          )
                        : _body(context, tokens),
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, AppColorTokens tokens) {
    final name = _facility?.name ?? 'Your facility';
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg2),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: AppSpacing.xxxl),
                    Container(
                      height: 76,
                      width: 76,
                  decoration: BoxDecoration(
                    color: tokens.primary,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.primary.withValues(alpha: 0.5),
                        blurRadius: 48,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.check_rounded, color: tokens.onPrimary, size: 40),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  "You're open\nfor business",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '$name is live. Share your booking link and the first guest '
                  'can book in seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _NextRow(
                  icon: Icons.link,
                  title: 'Your booking link is live',
                  subtitle: _bookingLink,
                  trailing: 'Copy',
                  onTap: _copyLink,
                ),
                const SizedBox(height: AppSpacing.md),
                _NextRow(
                  icon: Icons.card_membership_outlined,
                  title: 'Create a membership plan',
                  subtitle: 'Recommended next · 2 min',
                  chevron: true,
                  onTap: () => context.go(AppRoutes.membershipsNew),
                ),
                const SizedBox(height: AppSpacing.md),
                _NextRow(
                  icon: Icons.group_add_outlined,
                  title: 'Invite your front-desk staff',
                  subtitle: 'They get their own login',
                  chevron: true,
                  onTap: () => context.go(AppRoutes.profile),
                ),
                    const SizedBox(height: AppSpacing.xxxl),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg2, AppSpacing.md, AppSpacing.lg2, AppSpacing.lg),
          child: AuthGradientButton(
            label: 'Open my dashboard',
            onPressed: () => context.go(AppRoutes.dashboard),
          ),
        ),
      ],
    );
  }
}

class _NextRow extends StatelessWidget {
  const _NextRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.chevron = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.lg2),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 24, color: tokens.textSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        )),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: tokens.textSecondary)),
                  ],
                ),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: TextStyle(
                      fontSize: 15,
                      color: tokens.primary,
                      fontWeight: FontWeight.w700,
                    ))
              else if (chevron)
                Icon(Icons.chevron_right, size: 24, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
