import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/facility.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'onboarding_progress_bar.dart';

const _uuid = Uuid();

class CourtsSetupScreen extends ConsumerStatefulWidget {
  const CourtsSetupScreen({super.key});

  @override
  ConsumerState<CourtsSetupScreen> createState() => _CourtsSetupScreenState();
}

class _CourtsSetupScreenState extends ConsumerState<CourtsSetupScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  bool _isContinuing = false;
  String? _continueError;

  @override
  void initState() {
    super.initState();
    _load();
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
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      if (facilitySports.isEmpty) {
        if (mounted) context.go(AppRoutes.onboardingSports);
        return;
      }
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);

      setState(() {
        _facilityId = facility.id;
        _facilitySports = facilitySports;
        _sports = sports;
        _areas = areas;
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _addArea(FacilitySport facilitySport) async {
    final sport = _sports.where((s) => s.id == facilitySport.sportId).firstOrNull;
    final label = playingAreaLabelFor(sport?.code ?? 'OTHER');
    final existingForSport = _areas.where((a) => a.facilitySportId == facilitySport.id).toList();
    final usedNumbers = existingForSport
        .map((a) => int.tryParse(RegExp(r'(\d+)\s*$').firstMatch(a.name.trim())?.group(1) ?? '') ?? 0)
        .toList();
    final nextNumber = (usedNumbers.isEmpty ? 0 : usedNumbers.reduce((a, b) => a > b ? a : b)) + 1;

    final newArea = PlayingArea(
      id: _uuid.v4(),
      facilityId: _facilityId!,
      facilitySportId: facilitySport.id,
      sportId: facilitySport.sportId,
      name: '$label $nextNumber',
      areaType: 'INDOOR',
      status: 'ACTIVE',
      bookingEnabled: true,
      archived: false,
      displayOrder: existingForSport.length,
    );

    try {
      final created = await ref.read(playingAreaRepositoryProvider).createPlayingArea(newArea);
      setState(() => _areas = [..._areas, created]);
    } on AppException catch (e) {
      if (mounted) setState(() => _continueError = e.message);
    }
  }

  Future<void> _renameArea(PlayingArea area, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == area.name) return;
    try {
      final updated = await ref.read(playingAreaRepositoryProvider).updatePlayingArea(area.id, name: trimmed);
      setState(() {
        _areas = _areas.map((a) => a.id == area.id ? updated : a).toList();
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _continueError = e.message);
    }
  }

  Future<void> _updateAreaField(
    PlayingArea area, {
    String? areaType,
    String? status,
    bool? bookingEnabled,
  }) async {
    try {
      final updated = await ref
          .read(playingAreaRepositoryProvider)
          .updatePlayingArea(area.id, areaType: areaType, status: status, bookingEnabled: bookingEnabled);
      setState(() {
        _areas = _areas.map((a) => a.id == area.id ? updated : a).toList();
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _continueError = e.message);
    }
  }

  Future<void> _removeArea(PlayingArea area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this playing area?'),
        content: Text('This removes "${area.name}" from your facility.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(playingAreaRepositoryProvider).removePlayingArea(area.id);
      setState(() => _areas = _areas.where((a) => a.id != area.id).toList());
    } on AppException catch (e) {
      if (mounted) setState(() => _continueError = e.message);
    }
  }

  Future<void> _continue() async {
    final missing = _facilitySports.where((fs) => !_areas.any((a) => a.facilitySportId == fs.id));
    if (missing.isNotEmpty) {
      setState(() => _continueError = 'Add at least one playing area for every sport.');
      return;
    }

    setState(() {
      _isContinuing = true;
      _continueError = null;
    });
    try {
      await ref
          .read(facilityRepositoryProvider)
          .updateOnboardingStep(_facilityId!, OnboardingStep.operatingHours);
      await ref.read(sessionControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go(AppRoutes.onboardingOperatingHours);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _continueError = e.message);
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const OnboardingProgressBar(currentStep: 3)),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading courts & turfs…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set up your courts & turfs', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    const Text('Add the playing areas available at your facility.'),
                    const SizedBox(height: AppSpacing.xl),
                    if (_continueError != null) ...[
                      Text(_continueError!, style: const TextStyle(color: AppColors.destructive)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ..._facilitySports.map((fs) {
                      final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
                      final label = playingAreaLabelFor(sport?.code ?? 'OTHER');
                      final areasForSport = _areas.where((a) => a.facilitySportId == fs.id).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fs.customSportName ?? sport?.name ?? 'Sport',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (areasForSport.isEmpty)
                                Text('No ${label.toLowerCase()}s added yet.'),
                              ...areasForSport.map(
                                (area) => Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                  child: _PlayingAreaRow(
                                    area: area,
                                    onRename: (name) => _renameArea(area, name),
                                    onRemove: () => _removeArea(area),
                                    onAreaTypeChanged: (v) => _updateAreaField(area, areaType: v),
                                    onStatusChanged: (v) => _updateAreaField(area, status: v),
                                    onBookingEnabledChanged: (v) => _updateAreaField(area, bookingEnabled: v),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SecondaryButton(
                                label: '+ Add $label',
                                onPressed: () => _addArea(fs),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Continue →',
                      loadingLabel: 'Saving…',
                      isLoading: _isContinuing,
                      onPressed: _continue,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PlayingAreaRow extends StatefulWidget {
  const _PlayingAreaRow({
    required this.area,
    required this.onRename,
    required this.onRemove,
    required this.onAreaTypeChanged,
    required this.onStatusChanged,
    required this.onBookingEnabledChanged,
  });

  final PlayingArea area;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;
  final ValueChanged<String> onAreaTypeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<bool> onBookingEnabledChanged;

  @override
  State<_PlayingAreaRow> createState() => _PlayingAreaRowState();
}

class _PlayingAreaRowState extends State<_PlayingAreaRow> {
  late final TextEditingController _controller = TextEditingController(text: widget.area.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: widget.onRename,
                  onEditingComplete: () => widget.onRename(_controller.text),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.destructive),
                tooltip: 'Remove',
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _InlineDropdown(
                label: 'Type',
                value: widget.area.areaType,
                options: const ['INDOOR', 'OUTDOOR'],
                onChanged: widget.onAreaTypeChanged,
              ),
              _InlineDropdown(
                label: 'Status',
                value: widget.area.status,
                options: const ['ACTIVE', 'INACTIVE'],
                onChanged: widget.onStatusChanged,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bookable', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  Switch(value: widget.area.bookingEnabled, onChanged: widget.onBookingEnabledChanged),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineDropdown extends StatelessWidget {
  const _InlineDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        DropdownButton<String>(
          value: value,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o[0] + o.substring(1).toLowerCase())))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}