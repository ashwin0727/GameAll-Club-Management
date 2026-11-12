import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_widgets.dart' show AuthGradientButton;
import 'intro_art.dart';
import 'welcome_screen.dart' show introBackground, introPurple;

/// A row of boxes for a one-time code, one digit per box. A real (invisible) text field sits on top of the boxes, so the keyboard, paste,
/// the SMS autofill suggestion and Backspace all behave like any other field. Tapping the boxes focuses it.
class OtpBoxes extends StatelessWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onSubmitted,
    this.count = 6,
    this.enabled = true,
    this.hasError = false,
    this.fieldKey = const ValueKey('otp-field'),
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;
  final int count;
  final bool enabled;
  final bool hasError;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        // Up to 48 wide; on a narrow phone the boxes shrink so all of them always fit.
        final box = ((constraints.maxWidth - gap * (count - 1)) / count).clamp(30.0, 48.0);
        return Semantics(
          textField: true,
          label: 'One-time code, $count digits',
          child: AnimatedBuilder(
            animation: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final text = controller.text;
              final active = focusNode.hasFocus ? text.length.clamp(0, count - 1) : -1;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < count; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        _Box(
                          width: box,
                          char: i < text.length ? text[i] : '',
                          active: i == active,
                          error: hasError,
                        ),
                      ],
                    ],
                  ),
                  // The real field: invisible, but it still takes the taps and the typing.
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        key: fieldKey,
                        controller: controller,
                        focusNode: focusNode,
                        enabled: enabled,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        maxLength: count,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                        onChanged: (_) => onChanged(),
                        onSubmitted: (_) => onSubmitted?.call(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.width, required this.char, required this.active, required this.error});

  final double width;
  final String char;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final border = error ? const Color(0xFFC62828) : (active ? introPurple : const Color(0xFFE5E1EF));
    return Container(
      width: width,
      height: width * 1.18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: active || error ? 1.8 : 1.2),
        boxShadow: [BoxShadow(color: introPurple.withValues(alpha: active ? 0.14 : 0.06), blurRadius: active ? 10 : 6, offset: const Offset(0, 2))],
      ),
      child: Text(char, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF171717))),
    );
  }
}

/// "Resend OTP in **00:24**", and a "Resend OTP" button once the countdown is over.
class OtpResendRow extends StatelessWidget {
  const OtpResendRow({super.key, required this.secondsLeft, required this.onResend, this.busy = false, this.label = 'Resend OTP'});

  final int secondsLeft;
  final VoidCallback onResend;
  final bool busy;
  final String label;

  static String clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (secondsLeft > 0) {
      return Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 16, color: Color(0xFF555555)),
          children: [
            TextSpan(text: '$label in '),
            TextSpan(text: clock(secondsLeft), style: const TextStyle(fontWeight: FontWeight.w700, color: introPurple)),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    return TextButton(
      key: const ValueKey('otp-resend'),
      onPressed: busy ? null : onResend,
      style: TextButton.styleFrom(
        foregroundColor: introPurple,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

/// The page every code-entry step shares: back arrow, a picture, a title, "we've sent a code to ...", the code boxes, and the
/// Verify & Continue button pinned at the bottom.
class OtpPageFrame extends StatelessWidget {
  const OtpPageFrame({
    super.key,
    required this.onBack,
    required this.art,
    required this.title,
    required this.lead,
    required this.strong,
    required this.body,
    required this.buttonLabel,
    required this.onSubmit,
    this.busy = false,
    this.message,
    this.messageIsError = true,
    this.backEnabled = true,
  });

  final VoidCallback onBack;
  final IntroArtKind art;
  final String title;

  /// "We've sent a 6-digit OTP to"
  final String lead;

  /// The number or address, in bold under the lead line.
  final String strong;

  /// The code boxes and the resend row.
  final Widget body;
  final String buttonLabel;

  /// Null disables the button.
  final VoidCallback? onSubmit;
  final bool busy;
  final String? message;
  final bool messageIsError;
  final bool backEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: introBackground,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: IconButton(
                    key: const ValueKey('otp-back'),
                    onPressed: backEnabled ? onBack : null,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF171717),
                    tooltip: 'Back',
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(child: IntroArt(kind: art, width: (constraints.maxHeight * 0.34 * 240 / 200).clamp(150.0, 230.0))),
                                const SizedBox(height: 14),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
                                ),
                                const SizedBox(height: 10),
                                Text(lead, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF444444))),
                                const SizedBox(height: 4),
                                Text(
                                  strong,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF171717)),
                                ),
                                const SizedBox(height: 28),
                                body,
                                if (message != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    message!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 15, height: 1.35, color: messageIsError ? const Color(0xFFC62828) : const Color(0xFF0E9384)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AuthGradientButton(
                    key: const ValueKey('otp-submit'),
                    label: buttonLabel,
                    isLoading: busy,
                    radius: 16,
                    labelSize: 19,
                    labelWeight: FontWeight.w600,
                    onPressed: onSubmit,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
