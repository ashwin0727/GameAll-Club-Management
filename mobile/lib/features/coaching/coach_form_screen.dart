import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';

/// Add a coaching profile to an existing staff member — mirrors
/// src/features/coaching/components/add-coach-page.tsx. Never creates a
/// second account.
class CoachFormScreen extends ConsumerStatefulWidget {
  const CoachFormScreen({super.key});

  @override
  ConsumerState<CoachFormScreen> createState() => _CoachFormScreenState();
}

class _CoachFormScreenState extends ConsumerState<CoachFormScreen> {
  final _specialization = TextEditingController();
  final _experience = TextEditingController();
  final _certifications = TextEditingController();
  final _bio = TextEditingController();
  final _hourlyRate = TextEditingController();

  List<CoachCandidate> _candidates = const [];
  String? _userId;
  CoachStatus _status = CoachStatus.active;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCandidates());
  }

  @override
  void dispose() {
    for (final c in [_specialization, _experience, _certifications, _bio, _hourlyRate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    try {
      final list = await ref.read(coachingRepositoryProvider).listCoachCandidates(fid);
      if (mounted) setState(() { _candidates = list; _loading = false; });
    } on AppException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _save() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    if (_userId == null) {
      setState(() => _error = 'Select the staff member to make a coach.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rate = num.tryParse(_hourlyRate.text.trim());
      await ref.read(coachingRepositoryProvider).addCoach(
            facilityId: fid,
            userId: _userId!,
            specialization: _specialization.text.trim().isEmpty ? null : _specialization.text.trim(),
            experienceYears: num.tryParse(_experience.text.trim())?.toDouble(),
            certifications: _certifications.text.trim().isEmpty ? null : _certifications.text.trim(),
            bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            hourlyRateMinor: (rate != null && rate > 0) ? (rate * 100).round() : null,
            status: _status,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_MANAGE_COACHES')) {
      return const StaffPermissionDenied(title: 'Add Coach', message: "You don't have permission to manage coaches.");
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Coach')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _userId,
                    decoration: const InputDecoration(labelText: 'Staff member'),
                    items: _candidates.isEmpty
                        ? const [DropdownMenuItem(value: null, child: Text('Every staff member is already a coach'))]
                        : _candidates
                            .map((c) => DropdownMenuItem(
                                  value: c.userId,
                                  child: Text(c.title != null ? '${c.fullName} · ${c.title}' : c.fullName),
                                ))
                            .toList(),
                    onChanged: (v) => setState(() => _userId = v),
                  ),
                  const SizedBox(height: 4),
                  Text('A coach must already be a staff member — this never creates a new account.',
                      style: TextStyle(fontSize: 11, color: context.tokens.textSecondary)),
                  const SizedBox(height: AppSpacing.md),
                  TextField(controller: _specialization, decoration: const InputDecoration(labelText: 'Specialization')),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _experience,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Experience (yrs)'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _hourlyRate,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Hourly rate (₹)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _certifications, decoration: const InputDecoration(labelText: 'Certifications')),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _bio, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio')),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<CoachStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: CoachStatus.values
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v ?? CoachStatus.active),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: TextStyle(color: context.tokens.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(label: 'Add Coach', loadingLabel: 'Adding…', isLoading: _saving, onPressed: _save),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
      ),
    );
  }
}
