import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/states.dart';
import 'membership_batches_sheet.dart';
import 'membership_slot_card.dart';

String _todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The Owner Availability View — date picker, list of session slots each
/// rendered via the shared [MembershipSlotCard] (Capacity/Member Booked/
/// Unused/Released/Guest Available numbers, a status badge, and
/// Release/Restore/Book Guest actions), plus "Manage Batches". Mirrors
/// `membership-availability-view.tsx`.
class MembershipSessionsScreen extends ConsumerStatefulWidget {
  const MembershipSessionsScreen({super.key});

  @override
  ConsumerState<MembershipSessionsScreen> createState() => _MembershipSessionsScreenState();
}

class _MembershipSessionsScreenState extends ConsumerState<MembershipSessionsScreen> {
  String? _facilityId;
  bool _isLoading = true;
  String? _loadError;
  DateTime _date = DateTime.now();
  List<MembershipSessionSlot>? _slots;

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
        setState(() {
          _isLoading = false;
          _loadError = 'Complete your facility setup before managing membership sessions.';
        });
        return;
      }
      setState(() {
        _facilityId = facility.id;
        _isLoading = false;
      });
      await _reload();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _reload() async {
    if (_facilityId == null) return;
    setState(() => _slots = null);
    try {
      final slots = await ref.read(membershipSessionRepositoryProvider).listSessionsForDate(_facilityId!, _isoOf(_date));
      if (mounted) setState(() => _slots = slots);
    } on AppException catch (_) {
      if (mounted) setState(() => _slots = []);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _reload();
    }
  }

  Future<void> _openBatches() async {
    if (_facilityId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipBatchesSheet(facilityId: _facilityId!),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Sessions'),
        actions: [
          if (_facilityId != null)
            IconButton(icon: const Icon(Icons.event_note), tooltip: 'Manage Batches', onPressed: _openBatches),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading membership sessions…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(_isoOf(_date) == _todayIso() ? 'Today · ${_isoOf(_date)}' : _isoOf(_date)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_slots == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_slots!.isEmpty)
                      const EmptyStateView(message: 'No membership sessions today.')
                    else
                      ..._slots!.map(
                        (slot) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: MembershipSlotCard(facilityId: _facilityId!, slot: slot, onChanged: _reload),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}