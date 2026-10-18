import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sports/sport_selection.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/session_controller.dart';

/// One sport the facility offers, as the picker shows it.
class SportOption {
  const SportOption({required this.id, required this.name, required this.icon});

  final String id;
  final String name;
  final String icon;
}

/// The sports the facility offers (a custom name wins over the catalogue name), for the "All Sports" picker.
final facilitySportOptionsProvider = FutureProvider<List<SportOption>>((ref) async {
  final facilityId = ref.watch(sessionControllerProvider.select((s) => s.facility?.id));
  if (facilityId == null) return const [];
  final repo = ref.watch(sportsRepositoryProvider);
  final results = await Future.wait([repo.getFacilitySports(facilityId), repo.getActiveSports()]);
  final facilitySports = (results[0] as List<FacilitySport>).where((f) => f.enabled);
  final sports = results[1] as List<Sport>;
  return [
    for (final fs in facilitySports)
      () {
        final sport = sports.where((s) => s.id == fs.sportId).firstOrNull;
        return SportOption(
          id: fs.id,
          name: (fs.customSportName?.trim().isNotEmpty ?? false) ? fs.customSportName!.trim() : (sport?.name ?? 'Sport'),
          icon: sport?.icon ?? '🏅',
        );
      }(),
  ];
});

/// The user's choice: `null` = All Sports (the default), otherwise the ticked subset. Read it through
/// [sportScopeProvider], which checks it against the facility's real sports.
class SportSelectionNotifier extends Notifier<List<String>?> {
  @override
  List<String>? build() => null;

  void set(List<String>? ids) => state = ids;

  void selectAll() => state = null;
}

final sportSelectionProvider = NotifierProvider<SportSelectionNotifier, List<String>?>(SportSelectionNotifier.new);

/// The sports in view, ready to filter by.
class SportScope {
  const SportScope({required this.options, required this.selection, required this.ready});

  final List<SportOption> options;
  final ResolvedSportSelection selection;

  /// The sport list has loaded (or failed — then it is All Sports); until then nothing is hidden.
  final bool ready;

  bool get isAll => selection.isAll;

  /// The ids to send to the server / filter by: null = All Sports (nothing is filtered).
  List<String>? get ids => (!ready || selection.isAll || options.isEmpty) ? null : selection.ids;

  Set<String>? get idSet => ids?.toSet();

  String get label => sportSelectionLabel(selection, {for (final o in options) o.id: o.name});

  /// Stable text for effect / cache keys.
  String get key => ids?.join('|') ?? 'all';
}

final sportScopeProvider = Provider<SportScope>((ref) {
  final optionsAsync = ref.watch(facilitySportOptionsProvider);
  final stored = ref.watch(sportSelectionProvider);
  final options = optionsAsync.value ?? const <SportOption>[];
  return SportScope(
    options: options,
    selection: resolveSportSelection(stored, [for (final o in options) o.id]),
    ready: optionsAsync.hasValue || optionsAsync.hasError,
  );
});
