import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/facility.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import 'onboarding_scaffold.dart';

const _uuid = Uuid();

/// Screen 2 of the redesigned onboarding — "What can people play?". Merges
/// the old Sports and Courts steps: pick the sports, then dial in a court
/// count per sport with a stepper. Court rows are created/archived to match
/// the count on Continue.
class SportsSetupScreen extends ConsumerStatefulWidget {
  const SportsSetupScreen({super.key});

  @override
  ConsumerState<SportsSetupScreen> createState() => _SportsSetupScreenState();
}

class _SportsSetupScreenState extends ConsumerState<SportsSetupScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;
  List<Sport> _sports = [];
  final _customName = TextEditingController();

  /// Selected sport ids, in the order the owner tapped them.
  final List<String> _selected = [];

  /// Desired court count per selected sport id.
  final Map<String, int> _counts = {};

  /// Existing `courts` rows already saved for this facility, by sport id.
  final Map<String, List<PlayingArea>> _existingAreas = {};

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customName.dispose();
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
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final existing =
          await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      final areas =
          await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);

      _selected.clear();
      _counts.clear();
      _existingAreas.clear();
      for (final fs in existing) {
        _selected.add(fs.sportId);
        final forSport =
            areas.where((a) => a.facilitySportId == fs.id).toList();
        _existingAreas[fs.sportId] = forSport;
        _counts[fs.sportId] = forSport.isEmpty ? 1 : forSport.length;
        if (fs.customSportName != null) _customName.text = fs.customSportName!;
      }

      setState(() {
        _facilityId = facility.id;
        _sports = sports;
        _isLoading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Onboarding sports & courts load failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We couldn’t load this step. Please try again.';
      });
    }
  }

  void _toggleSport(Sport sport) {
    setState(() {
      if (_selected.contains(sport.id)) {
        _selected.remove(sport.id);
        _counts.remove(sport.id);
      } else {
        _selected.add(sport.id);
        _counts[sport.id] = _counts[sport.id] ?? 1;
      }
    });
  }

  void _setCount(String sportId, int value) {
    setState(() => _counts[sportId] = value.clamp(1, 40));
  }

  Sport? get _otherSport =>
      _sports.where((s) => s.code == otherSportCode).firstOrNull;

  int get _totalCourts =>
      _selected.fold(0, (sum, id) => sum + (_counts[id] ?? 0));

  Future<void> _submit() async {
    final facilityId = _facilityId;
    if (facilityId == null || _selected.isEmpty) return;

    final other = _otherSport;
    final otherSelected = other != null && _selected.contains(other.id);
    if (otherSelected && _customName.text.trim().length < 2) {
      setState(() => _submitError = 'Enter a sport name (at least 2 characters).');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final sportsRepo = ref.read(sportsRepositoryProvider);
      final areaRepo = ref.read(playingAreaRepositoryProvider);

      final saved = await sportsRepo.saveFacilitySports(
        facilityId,
        _selected.toList(),
        customSportName: otherSelected ? _customName.text.trim() : null,
      );

      // Reconcile court rows to the chosen counts.
      final currentAreas = await areaRepo.getPlayingAreas(facilityId);
      for (final fs in saved) {
        final want = _counts[fs.sportId] ?? 1;
        final have = currentAreas.where((a) => a.facilitySportId == fs.id).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
        final label = playingAreaLabelFor(sport?.code ?? 'OTHER');

        if (have.length < want) {
          for (var i = have.length; i < want; i++) {
            await areaRepo.createPlayingArea(PlayingArea(
              id: _uuid.v4(),
              facilityId: facilityId,
              facilitySportId: fs.id,
              sportId: fs.sportId,
              name: '$label ${i + 1}',
              areaType: 'INDOOR',
              status: 'ACTIVE',
              bookingEnabled: true,
              archived: false,
              displayOrder: i,
            ));
          }
        } else if (have.length > want) {
          for (final extra in have.sublist(want)) {
            await areaRepo.removePlayingArea(extra.id);
          }
        }
      }

      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(facilityId, OnboardingStep.pricing);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.push(AppRoutes.onboardingPricing);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.message);
    } catch (e, stack) {
      debugPrint('Onboarding sports & courts save failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _submitError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _loadError != null) {
      return OnboardingScaffold(
        stepIndex: 1,
        title: 'What can people play?',
        onBack: () => context.go(AppRoutes.onboardingFacility),
        footer: const SizedBox.shrink(),
        children: [
          SizedBox(
            height: 320,
            child: _isLoading
                ? const LoadingView(message: 'Loading…')
                : ErrorView(message: _loadError!, onRetry: _load),
          ),
        ],
      );
    }

    final other = _otherSport;
    final otherSelected = other != null && _selected.contains(other.id);

    return OnboardingScaffold(
      stepIndex: 1,
      title: 'What can people play?',
      subtitle: 'Pick your sports, then set how many courts each one has. '
          'Court names are generated and editable later.',
      onBack: () => context.go(AppRoutes.onboardingFacility),
      footer: AuthGradientButton(
        label: 'Next · pricing  ›',
        loadingLabel: 'Saving…',
        isLoading: _isSubmitting,
        onPressed: _selected.isEmpty ? null : _submit,
      ),
      children: [
        if (_submitError != null) ...[
          _ErrorText(_submitError!),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _sports.map((s) {
            return _SportChip(
              label: s.name,
              selected: _selected.contains(s.id),
              onTap: () => _toggleSport(s),
            );
          }).toList(),
        ),
        if (otherSelected) ...[
          const SizedBox(height: AppSpacing.lg),
          AppTextField(label: 'Sport name', controller: _customName),
        ],
        const SizedBox(height: AppSpacing.xl),
        ..._selected.map((id) {
          final sport = _sports.where((s) => s.id == id).firstOrNull;
          if (sport == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _SportCourtsCard(
              title: sport.code == otherSportCode && _customName.text.trim().isNotEmpty
                  ? _customName.text.trim()
                  : sport.name,
              iconAsset: sportIconAsset(sport.code),
              emoji: sport.icon,
              count: _counts[id] ?? 1,
              onChanged: (v) => _setCount(id, v),
              courtLabel: playingAreaLabelFor(sport.code),
            ),
          );
        }),
        if (_selected.isNotEmpty)
          Center(
            child: Text(
              '$_totalCourts court${_totalCourts == 1 ? '' : 's'} across '
              '${_selected.length} sport${_selected.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 13,
                color: context.tokens.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _SportChip extends StatelessWidget {
  const _SportChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.primary.withValues(alpha: 0.14) : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? tokens.primary : tokens.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 16, color: tokens.primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? tokens.primary : tokens.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SportCourtsCard extends StatelessWidget {
  const _SportCourtsCard({
    required this.title,
    required this.iconAsset,
    required this.emoji,
    required this.count,
    required this.onChanged,
    required this.courtLabel,
  });

  final String title;
  final String iconAsset;
  final String emoji;
  final int count;
  final ValueChanged<int> onChanged;
  final String courtLabel;

  @override
  Widget build(BuildContext context) {
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
              Image.asset(
                iconAsset,
                width: 52,
                height: 52,
                errorBuilder: (context, error, stack) =>
                    Text(emoji, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.remove,
                filled: false,
                onTap: count > 1 ? () => onChanged(count - 1) : null,
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                filled: true,
                onTap: () => onChanged(count + 1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: List.generate(count, (i) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: Text(
                  '$courtLabel ${i + 1}',
                  style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.filled, this.onTap});

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? (enabled ? tokens.primary : tokens.primary.withValues(alpha: 0.4))
              : Colors.transparent,
          border: filled ? null : Border.all(color: tokens.borderColor),
        ),
        child: Icon(
          icon,
          size: 18,
          color: filled
              ? tokens.onPrimary
              : (enabled ? tokens.textPrimary : tokens.textSecondary),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.tokens.destructive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: TextStyle(color: context.tokens.destructive, fontSize: 13),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
