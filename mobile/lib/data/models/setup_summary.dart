import 'facility.dart';
import 'sport.dart';
import 'playing_area.dart';
import 'operating_hours.dart';
import 'pricing.dart';

class MissingRequirement {
  const MissingRequirement({
    required this.code,
    required this.message,
    required this.actionLabel,
  });

  final String code;
  final String message;
  final String actionLabel;
}

/// Mirrors src/features/onboarding-summary/validation.ts's pure logic —
/// same rules, same requirement codes, evaluated against data pulled
/// through the same repositories every other screen uses.
class SetupSummary {
  const SetupSummary({
    required this.facility,
    required this.facilitySports,
    required this.sports,
    required this.playingAreas,
    required this.schedule,
    required this.pricingPlan,
  });

  final Facility facility;
  final List<FacilitySport> facilitySports;
  final List<Sport> sports;
  final List<PlayingArea> playingAreas;
  final OperatingSchedule? schedule;
  final PricingPlan? pricingPlan;

  bool get missingSports => facilitySports.isEmpty;
  bool get missingPlayingAreas => playingAreas.isEmpty;
  bool get missingOperatingHours =>
      schedule == null || !schedule!.days.any((d) => !d.isClosed);

  List<String> get sportsMissingPricing {
    final rules = pricingPlan?.rules ?? const <PricingRule>[];
    final missing = <String>[];
    for (final fs in facilitySports) {
      final hasSportLevelRule = rules.any(
        (r) => r.facilitySportId == fs.id && r.playingAreaId == null,
      );
      if (!hasSportLevelRule) {
        final sport = sports.where((s) => s.id == fs.sportId).firstOrNull;
        missing.add(fs.customSportName ?? sport?.name ?? 'this sport');
      }
    }
    return missing;
  }

  List<MissingRequirement> get missingRequirements {
    final requirements = <MissingRequirement>[];
    if (missingSports) {
      requirements.add(
        const MissingRequirement(
          code: 'SPORTS',
          message: 'No sports have been added to this facility.',
          actionLabel: 'Fix Sports',
        ),
      );
    }
    if (missingPlayingAreas) {
      requirements.add(
        const MissingRequirement(
          code: 'PLAYING_AREAS',
          message: 'No courts or turfs have been added.',
          actionLabel: 'Fix Courts & Turfs',
        ),
      );
    }
    if (missingOperatingHours) {
      requirements.add(
        const MissingRequirement(
          code: 'OPERATING_HOURS',
          message: 'Operating hours have not been configured.',
          actionLabel: 'Fix Operating Hours',
        ),
      );
    }
    if (!missingSports) {
      for (final sportName in sportsMissingPricing) {
        requirements.add(
          MissingRequirement(
            code: 'PRICING',
            message: 'Pricing has not been configured for $sportName.',
            actionLabel: 'Fix Pricing',
          ),
        );
      }
    }
    return requirements;
  }

  bool get isReady => missingRequirements.isEmpty;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}