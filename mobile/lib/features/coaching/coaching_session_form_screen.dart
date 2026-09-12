import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../maintenance/maintenance_court_options.dart';
import '../staff/staff_common.dart';

/// Create a coaching session — mirrors
/// src/features/coaching/components/session-wizard-page.tsx. Court, coach and
/// time are validated server-side against every other booking, session and
/// maintenance block.
class CoachingSessionFormScreen extends ConsumerStatefulWidget {
  const CoachingSessionFormScreen({super.key});

  @override
  ConsumerState<CoachingSessionFormScreen> createState() => _CoachingSessionFormScreenState();
}

class _CoachingSessionFormScreenState extends ConsumerState<CoachingSessionFormScreen> {
  final _capacity = TextEditingController();
  final _objective = TextEditingController();
  final _notes = TextEditingController();

  List<ProgramOption> _programs = const [];
  List<CoachOption> _coaches = const [];
  List<MaintenanceCourtOption> _courts = const [];
  bool _loading = true;

  String? _programId;
  String? _coachId;
  String? _courtId;
  DateTime _date = DateTime.now();
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  bool _autoEnroll = true;
  bool _confirmNow = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefs());
  }

  @override
  void dispose() {
    _capacity.dispose();
    _objective.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadRefs() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    try {
      final repo = ref.read(coachingRepositoryProvider);
      final programs = await repo.listProgramOptions(fid);
      final coaches = await repo.listCoachOptions(fid);
      final courts = await loadMaintenanceCourtOptions(ref, fid);
      if (mounted) {
        setState(() {
          _programs = programs;
          _coaches = coaches;
          _courts = courts;
          _loading = false;
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _onProgramChanged(String? id) {
    setState(() {
      _programId = id;
      final p = _programs.where((x) => x.id == id).firstOrNull;
      if (p != null) {
        if (_capacity.text.isEmpty) _capacity.text = '${p.defaultCapacity}';
        final endMinutes = _start.hour * 60 + _start.minute + p.defaultDurationMinutes;
        _end = TimeOfDay(hour: (endMinutes ~/ 60) % 24, minute: endMinutes % 60);
      }
    });
  }

  DateTime _combine(TimeOfDay t) => DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _save() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    if (_programId == null || _coachId == null || _courtId == null) {
      setState(() => _error = 'Choose a program, coach and court.');
      return;
    }
    final startAt = _combine(_start);
    final endAt = _combine(_end);
    if (!endAt.isAfter(startAt)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(coachingRepositoryProvider).createSession(
            facilityId: fid,
            programId: _programId!,
            coachId: _coachId!,
            courtId: _courtId!,
            startAt: startAt,
            endAt: endAt,
            capacity: int.tryParse(_capacity.text.trim()),
            objective: _objective.text.trim().isEmpty ? null : _objective.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            confirmNow: _confirmNow,
            autoEnroll: _autoEnroll,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
        // Return to the new session's detail via the caller isn't wired here;
        // the schedule/list refresh on pop(true). No further nav needed.
        assert(id.isNotEmpty);
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _start : _end);
    if (picked != null) setState(() => isStart ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_CREATE_SESSION')) {
      return const StaffPermissionDenied(
        title: 'New Session',
        message: "You don't have permission to create coaching sessions.",
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New Session')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _programId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Program'),
                    items: _programs
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _onProgramChanged,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _coachId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Coach'),
                    items: _coaches
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _coachId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _courtId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Court'),
                    items: _courts
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text('${c.name} · ${c.sportName}', overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _courtId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime(_date.year + 2),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date'),
                      child: Text(DateFormat('d MMM yyyy').format(_date)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickTime(true),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Start'),
                            child: Text(_start.format(context)),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickTime(false),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'End'),
                            child: Text(_end.format(context)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Capacity'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _objective, decoration: const InputDecoration(labelText: 'Objective (optional)')),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Add the program's active students to the roster"),
                    value: _autoEnroll,
                    onChanged: (v) => setState(() => _autoEnroll = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark as confirmed'),
                    value: _confirmNow,
                    onChanged: (v) => setState(() => _confirmNow = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: TextStyle(color: context.tokens.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(label: 'Create Session', loadingLabel: 'Creating…', isLoading: _saving, onPressed: _save),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
      ),
    );
  }
}
