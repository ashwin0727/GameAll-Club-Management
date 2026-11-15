import 'package:flutter/material.dart';

const _ink = Color(0xFF171717);
const _body = Color(0xFF3F3F46);
const _purple = Color(0xFF4817C2);
const _purpleTop = Color(0xFF5B21D6);
const _purpleDeep = Color(0xFF39109F);
const _line = Color(0xFFC9C4DA);
const _closeFill = Color(0xFFEEEAF7);
const _doorPicture = 'assets/images/logout_door.png';

/// "Log Out?" — the one confirmation every Log out / Sign out button goes through. Returns true only when the person confirms.
Future<bool> confirmLogout(BuildContext context) async {
  // Load the picture before the popup opens, so the picture and the words appear together.
  try {
    await precacheImage(const AssetImage(_doorPicture), context).timeout(const Duration(milliseconds: 400));
  } catch (_) {
    // show the popup anyway
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _LogoutDialog(),
  );
  return ok == true;
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFBFAFD),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Image.asset(_doorPicture, width: 190, fit: BoxFit.contain, gaplessPlayback: true)),
                  const SizedBox(height: 6),
                  const Text(
                    'Log Out?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 26, fontWeight: FontWeight.w700, color: _ink, height: 1.15),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Are you sure you want to log out of your GameAll account?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w400, color: _body, height: 1.35),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            key: const ValueKey('logout-cancel'),
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _ink,
                              side: const BorderSide(color: _line),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_purpleTop, _purple]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: _purple.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))],
                          ),
                          child: SizedBox(
                            height: 52,
                            child: TextButton.icon(
                              key: const ValueKey('logout-confirm'),
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                overlayColor: _purpleDeep,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.logout_rounded, size: 20),
                              label: const Text('Log Out'),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                  key: const ValueKey('logout-close'),
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
