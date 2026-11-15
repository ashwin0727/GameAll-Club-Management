import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _ink = Color(0xFF171717);
const _body = Color(0xFF555555);
const _purple = Color(0xFF4817C2);
const _purpleTop = Color(0xFF5B21D6);
const _purpleDeep = Color(0xFF39109F);
const _closeFill = Color(0xFFEEEAF7);
const _picture = 'assets/images/submit_review.png';
const _termsUrl = 'https://club.gameall.co/terms';
const _privacyUrl = 'https://club.gameall.co/privacy';

/// "Confirm & Submit for Review": shown when the owner taps Complete Setup on the Payout step. Both statements have to be ticked before
/// the setup is sent to GameAll for approval. Returns true only when the owner confirms.
Future<bool> confirmSubmitForReview(BuildContext context) async {
  // load the picture first, so it appears together with the words
  try {
    await precacheImage(const AssetImage(_picture), context).timeout(const Duration(milliseconds: 400));
  } catch (_) {
    // show the dialog anyway
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(context: context, builder: (_) => const _SubmitForReviewDialog());
  return ok == true;
}

class _SubmitForReviewDialog extends StatefulWidget {
  const _SubmitForReviewDialog();

  @override
  State<_SubmitForReviewDialog> createState() => _SubmitForReviewDialogState();
}

class _SubmitForReviewDialogState extends State<_SubmitForReviewDialog> {
  bool _accurate = false;
  bool _terms = false;
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()..onTap = () => _open(_termsUrl);
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()..onTap = () => _open(_privacyUrl);

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // nothing to do: the link simply does not open
    }
  }

  TextStyle _text({FontWeight weight = FontWeight.w400, Color color = _ink, double size = 14}) =>
      TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: weight, color: color, height: 1.35);

  Widget _tick({required Key key, required bool value, required ValueChanged<bool> onChanged, required Widget label}) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: IgnorePointer(child: Checkbox(value: value, onChanged: (_) {}, activeColor: _purple, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
            ),
            const SizedBox(width: 12),
            Expanded(child: label),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _accurate && _terms;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Image.asset(_picture, width: 210, fit: BoxFit.contain, gaplessPlayback: true)),
                  Text('Confirm & Submit for Review', textAlign: TextAlign.center, style: _text(weight: FontWeight.w700, size: 22)),
                  const SizedBox(height: 10),
                  Text(
                    'Please review and confirm the below statements to complete your facility setup and send it for GameAll’s approval.',
                    textAlign: TextAlign.center,
                    style: _text(color: _body, size: 14),
                  ),
                  const SizedBox(height: 16),
                  _tick(
                    key: const ValueKey('confirm-accurate'),
                    value: _accurate,
                    onChanged: (v) => setState(() => _accurate = v),
                    label: Text.rich(TextSpan(style: _text(), children: [
                      const TextSpan(text: 'I confirm '),
                      TextSpan(text: 'that all the information', style: _text(weight: FontWeight.w700)),
                      const TextSpan(text: ' I’ve provided about my facility (including address, contact, policies, amenities, and other details) is '),
                      TextSpan(text: 'true, accurate, and up to date.', style: _text(weight: FontWeight.w700)),
                    ])),
                  ),
                  const SizedBox(height: 6),
                  _tick(
                    key: const ValueKey('confirm-terms'),
                    value: _terms,
                    onChanged: (v) => setState(() => _terms = v),
                    label: Text.rich(TextSpan(style: _text(), children: [
                      const TextSpan(text: 'I have read and agree to GameAll’s '),
                      TextSpan(text: 'Terms and Conditions', recognizer: _termsTap, style: _text(weight: FontWeight.w700, color: _purple).copyWith(decoration: TextDecoration.underline)),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Privacy Policy', recognizer: _privacyTap, style: _text(weight: FontWeight.w700, color: _purple).copyWith(decoration: TextDecoration.underline)),
                      const TextSpan(text: '.'),
                    ])),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: ready ? 1 : 0.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_purpleTop, _purple]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: ready ? [BoxShadow(color: _purple.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))] : null,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: TextButton.icon(
                          key: const ValueKey('submit-for-review'),
                          onPressed: ready ? () => Navigator.pop(context, true) : null,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            overlayColor: _purpleDeep,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          icon: const Icon(Icons.send_outlined, size: 20),
                          label: const Text('Submit for Review'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      key: const ValueKey('submit-cancel'),
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ink,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: _purple.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: _closeFill,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey('submit-close'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context, false),
                  child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close, size: 18, color: _ink, semanticLabel: 'Close')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
