import 'dart:io';

import 'package:logger/logger.dart';
// FileOutput import needed due to bug in package.
// ignore: implementation_imports
import 'package:logger/src/outputs/file_output.dart';
import 'package:path_provider/path_provider.dart';

late final Logger logger;

/// Print log messages.
Future<void> initializeLogger(String name) async {
  final tempDir = await getTemporaryDirectory();
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '_');
  final logFile = File(
    '${tempDir.path}${Platform.pathSeparator}${name}_update_log_$timestamp.txt',
  );
  await logFile.create();

  logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      colors: stdout.supportsAnsiEscapes,
      lineLength: (stdout.hasTerminal) ? stdout.terminalColumns : 120,
    ),
    output: MultiOutput([
      ConsoleOutput(),
      FileOutput(file: logFile),
    ]),
  );
}
