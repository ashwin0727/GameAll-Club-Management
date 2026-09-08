import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/repository_providers.dart';

class MaintenanceCourtOption {
  const MaintenanceCourtOption({required this.id, required this.name, required this.sportName});
  final String id;
  final String name;
  final String sportName;
}

/// Court + sport labels for a facility — built from the existing
/// playing-areas/sports repositories, mirrors
/// src/features/maintenance/court-options.ts. No new "list courts" RPC.
Future<List<MaintenanceCourtOption>> loadMaintenanceCourtOptions(WidgetRef ref, String facilityId) async {
  final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facilityId);
  final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
  final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(facilityId);

  String sportName(String facilitySportId) {
    final fs = facilitySports.where((f) => f.id == facilitySportId).firstOrNull;
    if (fs == null) return 'Sport';
    if (fs.customSportName != null && fs.customSportName!.isNotEmpty) return fs.customSportName!;
    return sports.where((s) => s.id == fs.sportId).firstOrNull?.name ?? 'Sport';
  }

  final options = areas
      .where((a) => !a.archived)
      .map((a) => MaintenanceCourtOption(id: a.id, name: a.name, sportName: sportName(a.facilitySportId)))
      .toList();
  options.sort((a, b) => a.name.compareTo(b.name));
  return options;
}
