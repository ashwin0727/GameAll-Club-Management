import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/session_controller.dart';
import 'setup_ui.dart';

const _stepNames = ['Facility Information', 'Sports & Courts', 'Operating Hours', 'Pricing', 'Payout'];

/// Shown after "Complete Setup" until GameAll's admin approves the facility (or sends it back with a note). The router keeps the owner
/// and staff here; it polls the database so the dashboard opens by itself on approval.
class SetupReviewScreen extends ConsumerStatefulWidget {
  const SetupReviewScreen({super.key});

  @override
  ConsumerState<SetupReviewScreen> createState() => _SetupReviewScreenState();
}

class _SetupReviewScreenState extends ConsumerState<SetupReviewScreen> {
  Timer? _poll;
  bool _checking = false;
  bool _resubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await ref.read(sessionControllerProvider.notifier).refresh(); // the router leaves this screen once the status is APPROVED
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resubmit(String facilityId) async {
    setState(() {
      _resubmitting = true;
      _error = null;
    });
    try {
      await ref.read(payoutRepositoryProvider).resubmitForReview(facilityId);
      await ref.read(sessionControllerProvider.notifier).refresh();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send your setup for review. Please try again.');
    } finally {
      if (mounted) setState(() => _resubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final facility = session.facility;
    final rejected = facility?.setupReviewStatus == 'REJECTED';
    final isOwner = facility != null && facility.ownerId == session.user?.id;

    Widget next(IconData icon, String title, String text) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: SetupColors.activeBg.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: SetupColors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: setupText(size: 16, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(text, style: setupText(size: 14, color: const Color(0xFF444444), height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        );

    return SetupPage(
      footer: rejected && isOwner
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) SetupErrorBanner(_error!),
                Row(
                  children: [
                    Expanded(child: SetupButton(label: 'Dashboard', onPressed: () => context.go(AppRoutes.dashboard))),
                    const SizedBox(width: 8),
                    Expanded(child: SetupButton(label: 'Edit setup', onPressed: () => context.go(AppRoutes.onboardingFacility))),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: SetupButton(label: 'Send again', primary: true, loading: _resubmitting, loadingLabel: 'Sending…', onPressed: () => _resubmit(facility.id))),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: SetupButton(label: 'Check status', icon: Icons.refresh, loading: _checking, loadingLabel: 'Checking…', onPressed: _check)),
                const SizedBox(width: 12),
                Expanded(child: SetupButton(label: 'Go to Dashboard', primary: true, trailingIcon: Icons.arrow_forward, onPressed: () => context.go(AppRoutes.dashboard))),
              ],
            ),
      children: [
        Center(
          child: Container(
            height: 96,
            width: 96,
            decoration: BoxDecoration(color: rejected ? const Color(0xFFFDECEA) : SetupColors.activeBg, shape: BoxShape.circle),
            child: Icon(rejected ? Icons.report_problem_outlined : Icons.fact_check_outlined, size: 48, color: rejected ? SetupColors.error : SetupColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            style: setupText(size: 26, weight: FontWeight.w700, height: 1.2),
            children: [
              const TextSpan(text: 'Your Facility Setup '),
              TextSpan(text: rejected ? 'Needs Changes' : 'is Under Review', style: TextStyle(color: rejected ? SetupColors.error : SetupColors.primary)),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          rejected
              ? 'Our team reviewed ${facility?.name ?? 'your facility'} and needs something fixed before it can go live.'
              : 'Thank you for completing your facility setup. Our team is currently reviewing your details and documents.',
          textAlign: TextAlign.center,
          style: setupText(size: 15, color: const Color(0xFF2B2B2B), height: 1.4),
        ),
        const SizedBox(height: 14),
        if (rejected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFDF3F3), border: Border.all(color: const Color(0xFFF3C9C9)), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What to fix', style: setupText(size: 13, weight: FontWeight.w600, color: SetupColors.error)),
                const SizedBox(height: 4),
                Text(facility?.setupReviewNote ?? 'Please review your setup and send it again.', style: setupText(size: 14, height: 1.4)),
              ],
            ),
          )
        else
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFEFE8FF), borderRadius: BorderRadius.circular(99)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, size: 22, color: SetupColors.primary),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text.rich(
                      TextSpan(style: setupText(size: 14, weight: FontWeight.w500), children: [
                        const TextSpan(text: 'Approval usually takes up to '),
                        TextSpan(text: '24 hours.', style: setupText(size: 14, weight: FontWeight.w700, color: SetupColors.primary)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF1FAF3), border: Border.all(color: const Color(0xFFBFE5C6)), borderRadius: BorderRadius.circular(14)),
          child: Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              for (final s in _stepNames)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(height: 24, width: 24, decoration: const BoxDecoration(color: Color(0xFF2E9D4F), shape: BoxShape.circle), child: const Icon(Icons.check, size: 15, color: Colors.white)),
                    const SizedBox(width: 8),
                    Text(s, style: setupText(size: 13, weight: FontWeight.w500)),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('What’s Next?', style: setupText(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        next(Icons.how_to_reg_outlined, 'Review by Our Team', 'We’ll verify your facility details, pricing, and payout information.'),
        const SizedBox(height: 10),
        next(Icons.verified_outlined, 'Get Approved', 'You’ll receive a notification once your setup is approved.'),
        const SizedBox(height: 10),
        next(Icons.rocket_launch_outlined, 'Start Using GameAll', 'After approval, you can access your facility dashboard and start managing your bookings, memberships, and more.'),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFEFE8FF), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('You’ll receive an email and in-app notification once your facility is approved.', style: setupText(size: 13, weight: FontWeight.w500, height: 1.35))),
            ],
          ),
        ),
      ],
    );
  }
}
