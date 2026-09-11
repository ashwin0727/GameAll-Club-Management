import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import 'tournament_app_config.dart';
import 'tournament_app_launcher.dart';
import 'tournament_app_preview.dart';

/// Handoff / bridge screen for the SEPARATE Tournament Management application.
/// GameAll Facility Management builds no tournament features itself — this
/// screen explains the dedicated app and opens or links to it.
///
/// Mobile-first composition: back → one preview → heading → short description →
/// CTA → features → why separate → "already have the app?".
class TournamentManagementScreen extends StatefulWidget {
  const TournamentManagementScreen({
    super.key,
    this.config = const TournamentAppConfig(),
    this.launcher,
  });

  final TournamentAppConfig config;
  final TournamentAppLauncher? launcher;

  @override
  State<TournamentManagementScreen> createState() => _TournamentManagementScreenState();
}

class _TournamentManagementScreenState extends State<TournamentManagementScreen> {
  late final TournamentAppLauncher _launcher = widget.launcher ?? TournamentAppLauncher();
  bool _launchFailed = false;

  TournamentAppConfig get _cfg => widget.config;

  Future<void> _open() async {
    setState(() => _launchFailed = false);
    final result = await _launcher.open(_cfg.openUrl);
    if (!mounted) return;
    if (result == TournamentLaunchResult.failed) {
      setState(() => _launchFailed = true);
    }
  }

  Future<void> _download() async {
    await _launcher.open(_cfg.downloadUrl);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasOpen = _cfg.openUrl != null;
    final hasDownload = _cfg.downloadUrl != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tournament Management')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
          children: [
            Center(child: TournamentAppPreview(previews: _cfg.previewAssets)),
            const SizedBox(height: AppSpacing.xl),
            Text('POWERED BY GAMEALL',
                style: AppTypography.caption(context).copyWith(
                  color: t.primary,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: AppSpacing.xs),
            Text('Bigger Tournaments.\nBetter Experiences.',
                style: AppTypography.sectionTitle(context).copyWith(fontSize: 26, height: 1.2, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tournament Management is a dedicated GameAll app for organizers and players — '
              'draws, registrations, schedules and live results. Your facility operations stay right here.',
              style: AppTypography.body(context).copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (_launchFailed) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("We couldn't open the Tournament App.",
                        style: AppTypography.rowTitle(context).copyWith(color: t.destructive)),
                    const SizedBox(height: 4),
                    Text('Install it from the store, or try again.',
                        style: AppTypography.caption(context).copyWith(color: t.textSecondary)),
                    const SizedBox(height: AppSpacing.md),
                    if (hasDownload)
                      SecondaryButton(label: 'Download App', onPressed: _download),
                    if (hasOpen) ...[
                      const SizedBox(height: AppSpacing.sm),
                      PrimaryButton(label: 'Try Again', onPressed: _open),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (hasOpen)
              PrimaryButton(label: 'Open Tournament App', onPressed: _open, icon: Icons.open_in_new)
            else if (hasDownload)
              PrimaryButton(label: 'Download App', onPressed: _download, icon: Icons.open_in_new)
            else
              Text(
                "The Tournament App links aren't configured yet.",
                style: AppTypography.caption(context).copyWith(color: t.textSecondary),
              ),
            if (hasOpen && hasDownload) ...[
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(label: 'Download App', onPressed: _download),
            ],
            if (_cfg.availabilityLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(_cfg.availabilityLabel!,
                    style: AppTypography.caption(context).copyWith(color: t.textSecondary)),
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
            Text('Everything You Need for Tournament Success',
                style: AppTypography.sectionTitle(context).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            ..._features.map((f) => _InfoCard(icon: f.$1, title: f.$2, body: f.$3)),

            const SizedBox(height: AppSpacing.xl),
            Text('Why a separate application?',
                style: AppTypography.sectionTitle(context).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Running a tournament and running a facility are different jobs. Focused apps keep each one fast and reliable.',
              style: AppTypography.caption(context).copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            ..._whySeparate.map((f) => _InfoCard(icon: f.$1, title: f.$2, body: f.$3)),

            const SizedBox(height: AppSpacing.xl),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Already have the app?', style: AppTypography.rowTitle(context)),
                  const SizedBox(height: 4),
                  Text('Jump straight into your organizer dashboard.',
                      style: AppTypography.caption(context).copyWith(color: t.textSecondary)),
                  if (hasOpen) ...[
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(label: 'Open Tournament App', onPressed: _open, icon: Icons.open_in_new),
                  ] else if (hasDownload) ...[
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(label: 'Download App', onPressed: _download, icon: Icons.open_in_new),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _features = <(IconData, String, String)>[
  (Icons.emoji_events_outlined, 'Create & Manage Tournaments',
      'Single elimination, round robin or league formats with categories, seeding and venue rules.'),
  (Icons.groups_outlined, 'Player & Team Registrations',
      'Open registration links, collect entries and payments, and manage waitlists without spreadsheets.'),
  (Icons.calendar_month_outlined, 'Fixtures & Scheduling',
      'Auto-generate draws and match schedules across courts and days, then adjust with a drag.'),
  (Icons.scoreboard_outlined, 'Live Scores & Results',
      'Update match scores in real time and publish standings and brackets your players can follow.'),
  (Icons.checklist_outlined, 'Tournament Operations',
      'Coordinate officials, notifications and on-site check-in from one organizer dashboard.'),
];

const _whySeparate = <(IconData, String, String)>[
  (Icons.rocket_launch_outlined, 'Built for match day',
      'A focused organizer tool with draws, live scoring and brackets — designed for the pace of a live event.'),
  (Icons.verified_user_outlined, 'Your facility stays clean',
      'Bookings, memberships and finance keep working exactly as they do today, with no tournament clutter.'),
  (Icons.alt_route_outlined, 'Independent updates',
      'The tournament team ships new formats and features on its own schedule without disrupting operations here.'),
];

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: t.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.rowTitle(context)),
                  const SizedBox(height: 2),
                  Text(body, style: AppTypography.caption(context).copyWith(color: t.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
