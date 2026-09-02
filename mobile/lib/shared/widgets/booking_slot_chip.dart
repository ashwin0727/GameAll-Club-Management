import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// The one reusable Booking Slot component (spec §17) — every screen that
/// shows a court's time slots (the availability list, Quick Booking, the
/// reschedule picker) renders this instead of hand-rolling its own chip.
/// A booked slot is visually and interactively inert — it is never a
/// disabled-but-still-tappable control.
class BookingSlotChip extends StatefulWidget {
  const BookingSlotChip({
    super.key,
    required this.label,
    required this.available,
    required this.selected,
    this.onTap,
    this.locked = false,
  });

  final String label;
  final bool available;
  final bool selected;
  final VoidCallback? onTap;

  /// True when this cell falls inside a membership batch's protected
  /// window (see findMembershipSlot in features/bookings/booking_slots.dart).
  /// A locked slot is always tappable — regardless of [available] — since
  /// tapping it opens the membership slot panel rather than the normal
  /// booking flow, and is rendered in a visually distinct style so it's
  /// never confused with a plain available/booked cell.
  final bool locked;

  @override
  State<BookingSlotChip> createState() => _BookingSlotChipState();
}

class _BookingSlotChipState extends State<BookingSlotChip> {
  bool _pressed = false;

  bool get _tappable => widget.locked || widget.available;

  void _handleTap() {
    if (!_tappable || widget.onTap == null) return;
    HapticFeedback.selectionClick();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color border;
    final Color foreground;

    if (widget.selected) {
      background = AppColors.primary;
      border = AppColors.primary;
      foreground = Colors.white;
    } else if (widget.locked) {
      background = AppColors.info.withValues(alpha: 0.1);
      border = AppColors.info.withValues(alpha: 0.4);
      foreground = AppColors.info;
    } else if (!widget.available) {
      background = AppColors.mutedBackground;
      border = AppColors.border;
      foreground = AppColors.muted;
    } else {
      background = AppColors.success.withValues(alpha: 0.1);
      border = AppColors.success.withValues(alpha: 0.4);
      foreground = AppColors.success;
    }

    final subtitle = widget.selected
        ? 'Selected'
        : widget.locked
            ? 'Membership'
            : (widget.available ? 'Available' : 'Booked');

    return GestureDetector(
      onTapDown: _tappable ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _tappable ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: _tappable ? () => setState(() => _pressed = false) : null,
      onTap: _handleTap,
      child: Semantics(
        button: true,
        enabled: _tappable,
        selected: widget.selected,
        label: widget.locked
            ? '${widget.label}, membership protected'
            : widget.available
                ? (widget.selected ? '${widget.label}, selected' : '${widget.label}, available')
                : '${widget.label}, booked',
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.standard,
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget, minWidth: 72),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              color: background,
              border: Border.all(color: border, width: widget.selected ? 2 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.locked ? '🔒 ${widget.label}' : widget.label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: foreground),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 9, color: widget.selected ? Colors.white70 : AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}