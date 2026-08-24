import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/guest.dart';
import '../../data/models/membership_session.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';

/// Search-or-create a guest (reusing the existing `GuestRepository`
/// search/find-or-create flow, same as the Guest Players feature), then
/// book them into a session's released capacity. Mirrors
/// `book-guest-slot-dialog.tsx`. Returns `true` via `Navigator.pop` on a
/// successful booking.
class BookGuestSlotSheet extends ConsumerStatefulWidget {
  const BookGuestSlotSheet({super.key, required this.facilityId, required this.slot});

  final String facilityId;
  final MembershipSessionSlot slot;

  @override
  ConsumerState<BookGuestSlotSheet> createState() => _BookGuestSlotSheetState();
}

class _BookGuestSlotSheetState extends ConsumerState<BookGuestSlotSheet> {
  final _queryController = TextEditingController();
  List<GuestPlayer> _results = [];
  GuestPlayer? _selectedGuest;
  bool _showNewGuestForm = false;
  final _newNameController = TextEditingController();
  final _newPhoneController = TextEditingController();
  bool _isBooking = false;
  String? _error;

  @override
  void dispose() {
    _queryController.dispose();
    _newNameController.dispose();
    _newPhoneController.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    if (value.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    try {
      final results = await ref.read(guestRepositoryProvider).searchGuests(widget.facilityId, value);
      if (mounted) setState(() => _results = results);
    } on AppException catch (_) {
      // Search errors stay silent — the field simply shows no results.
    }
  }

  Future<void> _saveNewGuest() async {
    final nameError = Validators.name(_newNameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final phoneError = Validators.optionalPhone(_newPhoneController.text);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    try {
      final guest = await ref.read(guestRepositoryProvider).findOrCreateGuest(
        GuestInput(
          facilityId: widget.facilityId,
          name: _newNameController.text.trim(),
          phone: _newPhoneController.text.trim().isNotEmpty ? _newPhoneController.text.trim() : null,
        ),
      );
      setState(() {
        _selectedGuest = guest;
        _showNewGuestForm = false;
        _error = null;
      });
    } on AppException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _confirm() async {
    final guest = _selectedGuest;
    if (guest == null) {
      setState(() => _error = 'Search for and select a guest, or create a new one.');
      return;
    }
    setState(() {
      _isBooking = true;
      _error = null;
    });
    try {
      await ref
          .read(membershipSessionRepositoryProvider)
          .bookGuestSlot(widget.slot.batchId, widget.slot.sessionDate, guest.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Book Guest Slot', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.slot.batchName} · ${widget.slot.courtName} · ${widget.slot.startTime.substring(0, 5)}–${widget.slot.endTime.substring(0, 5)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_selectedGuest != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_selectedGuest!.name),
                subtitle: _selectedGuest!.phone != null ? Text(_selectedGuest!.phone!) : null,
                trailing: TextButton(onPressed: () => setState(() => _selectedGuest = null), child: const Text('Change')),
              )
            else if (_showNewGuestForm) ...[
              TextField(controller: _newNameController, decoration: const InputDecoration(labelText: 'Guest name')),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _newPhoneController,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  FilledButton(onPressed: _saveNewGuest, child: const Text('Save Guest')),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(onPressed: () => setState(() => _showNewGuestForm = false), child: const Text('Cancel')),
                ],
              ),
            ] else ...[
              TextField(
                controller: _queryController,
                onChanged: _search,
                decoration: const InputDecoration(labelText: 'Search guests', hintText: 'Name or phone'),
              ),
              ..._results.map(
                (g) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(g.name),
                  subtitle: g.phone != null ? Text(g.phone!) : null,
                  onTap: () => setState(() {
                    _selectedGuest = g;
                    _results = [];
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => setState(() => _showNewGuestForm = true),
                child: const Text('+ Create New Guest'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Confirm Booking',
              loadingLabel: 'Booking…',
              isLoading: _isBooking,
              onPressed: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}