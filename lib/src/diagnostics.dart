import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Every debug APK has a visible, verifiable build ID, injected by CI.
/// No backend, analytics endpoint, or third-party crash reporter is used.
const hoticeBuildId = String.fromEnvironment(
  'HOTICE_BUILD_ID',
  defaultValue: 'LOCAL',
);
const hoticeAppVersion = '0.2.0';

/// In-memory first-failure recorder for debug diagnostics. A later framework
/// cleanup failure can mask an earlier build exception (for example:
/// '_dependents.isEmpty'). Keep the FIRST exception and full local debug log.
class HoticeDiagnostics {
  HoticeDiagnostics._();

  static String? firstException;
  static String? firstStack;
  static String? lastException;

  static void record(Object exception, StackTrace? stack) {
    final message = exception.toString();
    firstException ??= message;
    if (firstStack == null && stack != null) {
      firstStack = stack.toString();
    }
    lastException = message;
    debugPrint('HOTICE [$hoticeBuildId] FIRST: $firstException');
    debugPrint('HOTICE [$hoticeBuildId] CURRENT: $message');
    if (stack != null) debugPrintStack(stackTrace: stack);
  }

  static String report([String? widgetError]) {
    return 'HOTICE $hoticeAppVersion ($hoticeBuildId)\n'
        'First exception: ${firstException ?? widgetError ?? 'unavailable'}\n'
        'Current exception: ${lastException ?? widgetError ?? 'unavailable'}\n'
        'First stack:\n${firstStack ?? 'unavailable'}';
  }

  /// Install before runApp, not after the first home route is built.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    ErrorWidget.builder = (details) {
      record(details.exception, details.stack);
      // Basic widgets only: error fallback must not itself depend on the
      // application's Theme, Material, Scaffold or Navigator.
      return Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF18121C),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HOTICE TEST DIAGNOSTICS',
                  style: TextStyle(
                    color: Color(0xFF9AE6FF),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Please screenshot this screen. The first error is the '
                  'important one.',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
                ),
                const SizedBox(height: 14),
                Text(
                  report(details.exceptionAsString()).substring(
                    0,
                    report(details.exceptionAsString()).length > 1900
                        ? 1900
                        : report(details.exceptionAsString()).length,
                  ),
                  style: const TextStyle(
                    color: Color(0xFFFFDCE4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Clipboard.setData(
                    ClipboardData(text: report(details.exceptionAsString())),
                  ),
                  child: const Text(
                    'COPY FULL ERROR REPORT',
                    style: TextStyle(
                      color: Color(0xFF9AE6FF),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    };
  }
}
