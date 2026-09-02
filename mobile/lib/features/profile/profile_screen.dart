import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../authentication/session_controller.dart';

/// Profile — spec §"Profile": kept simple, backed entirely by the real
/// signed-in session (never fabricated fields like "My Reviews" or
/// "Payment Methods", which have no backing data in this app — see the
/// redesign summary for why the full player-app Profile spec doesn't
/// map 1:1 onto GameAll's facility-management mobile app).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final facility = session.facility;
    final themeMode = ref.watch(themeModeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ResponsivePage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Row(
                  children: [
                    AppAvatar(name: user?.fullName ?? '?', size: AppAvatarSize.large),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user?.fullName ?? 'Unknown',
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(color: context.tokens.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (facility != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            StatusBadge(label: facility.name, tone: StatusTone.info, icon: Icons.storefront),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: 'Appearance'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ThemeOption(
                      label: 'System',
                      icon: Icons.brightness_auto,
                      selected: themeMode == ThemeMode.system,
                      onTap: () => ref.read(themeModeControllerProvider.notifier).setMode(ThemeMode.system),
                    ),
                    Divider(height: 1, color: context.tokens.borderColor),
                    _ThemeOption(
                      label: 'Light',
                      icon: Icons.light_mode_outlined,
                      selected: themeMode == ThemeMode.light,
                      onTap: () => ref.read(themeModeControllerProvider.notifier).setMode(ThemeMode.light),
                    ),
                    Divider(height: 1, color: context.tokens.borderColor),
                    _ThemeOption(
                      label: 'Dark',
                      icon: Icons.dark_mode_outlined,
                      selected: themeMode == ThemeMode.dark,
                      onTap: () => ref.read(themeModeControllerProvider.notifier).setMode(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: 'Account'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InfoRow(label: 'Role', value: (user?.role ?? '').isEmpty ? '—' : _titleCase(user!.role)),
                    if (facility != null && facility.address.city.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _InfoRow(label: 'City', value: facility.address.city),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              DangerButton(
                label: 'Sign Out',
                onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.profile),
    );
  }

  static String _titleCase(String value) => value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: context.tokens.textSecondary))),
        Flexible(child: Text(value, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.huge),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? tokens.primary : tokens.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label)),
            if (selected) Icon(Icons.check, color: tokens.primary, size: 20),
          ],
        ),
      ),
    );
  }
}