import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../authentication/session_controller.dart';

/// The line shown when a draft is saved (the same words as the website).
const String kDraftSavedMessage = 'Draft saved. You can pick up where you left off.';

/// Saves a step's draft by itself.
///
/// It watches [signature], a short string that changes whenever anything the person can edit changes. Once something has changed and
/// then stayed untouched for [quiet] (10 seconds), [save] runs and, if it saved, [onSaved] shows the "Draft saved" notice. Typing
/// keeps pushing the save back, so it never fires mid-sentence, and the same content is never saved twice. [save] returns false when
/// there was nothing it could save (the step is mid-way, or a manual save is running); that is not an error and is not shown.
///
/// Nothing here touches the screen: no setState, no rebuilds. The only repeating work is comparing two short strings once a second.
class DraftAutosave {
  DraftAutosave({
    required this.signature,
    required this.save,
    required this.onSaved,
    this.quiet = const Duration(seconds: 10),
    this.poll = const Duration(seconds: 1),
  });

  final String Function() signature;
  final Future<bool> Function() save;
  final VoidCallback onSaved;
  final Duration quiet;
  final Duration poll;

  Timer? _timer;
  String _saved = '';
  String _lastSeen = '';
  String _skipped = '';
  int _stableTicks = 0;
  bool _running = false;
  bool _disposed = false;

  int get _ticksNeeded => (quiet.inMilliseconds / poll.inMilliseconds).ceil();

  /// Starts watching. What is on screen right now counts as "already saved": only later changes are saved.
  void start() {
    _saved = _lastSeen = signature();
    _timer?.cancel();
    _timer = Timer.periodic(poll, (_) => _tick());
  }

  /// Declares the current content saved (after the person saved or moved on by themselves), so it is not saved again.
  void markSaved() {
    if (_disposed) return;
    _saved = _lastSeen = signature();
    _stableTicks = 0;
  }

  Future<void> _tick() async {
    if (_running || _disposed) return;
    final now = signature();
    if (now == _saved) {
      _lastSeen = now;
      _stableTicks = 0;
      return;
    }
    if (now != _lastSeen) {
      // still being edited: start the quiet period over
      _lastSeen = now;
      _stableTicks = 0;
      return;
    }
    if (now == _skipped) return; // already found unsaveable as it is; wait for the next change
    if (++_stableTicks < _ticksNeeded) return;

    _running = true;
    try {
      final saved = await save();
      if (_disposed) return;
      if (saved) {
        _saved = now;
        _skipped = '';
        onSaved();
      } else {
        _skipped = now;
      }
    } catch (e, stack) {
      debugPrint('Draft autosave failed: $e\n$stack');
      _skipped = now; // do not hammer a failing request; the next change tries again
    } finally {
      _stableTicks = 0;
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// Refreshes the signed-in session (the owner's facility and setup step) without making anyone wait for it. The next step opens at
/// once; this catches the app's copy up behind it.
void refreshSessionInBackground(WidgetRef ref) {
  unawaited(ref.read(sessionControllerProvider.notifier).refresh().catchError((Object e) {
    debugPrint('Background session refresh failed: $e');
  }));
}

/// The id of the owner's facility as the app already knows it, if it does. Lets a step start its data requests straight away instead of
/// first waiting to learn the id.
String? knownFacilityId(WidgetRef ref) => ref.read(sessionControllerProvider).facility?.id;
