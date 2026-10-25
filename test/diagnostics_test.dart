import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/diagnostics.dart';

void main() {
  test('first Flutter exception is preserved even if cleanup fails later', () {
    HoticeDiagnostics.record(
      StateError('PRIMARY render failure'),
      StackTrace.fromString('hotice/dummy.dart:12'),
    );
    HoticeDiagnostics.record(
      StateError('_dependents.isEmpty secondary failure'),
      StackTrace.fromString('framework.dart:6281'),
    );

    final report = HoticeDiagnostics.report();
    expect(report, contains('PRIMARY render failure'));
    expect(report, contains('hotice/dummy.dart:12'));
    expect(report, contains('_dependents.isEmpty secondary failure'));
    expect(report, contains('HOTICE 0.2.0'));
    expect(HoticeDiagnostics.firstException, contains('PRIMARY'));
  });
}
