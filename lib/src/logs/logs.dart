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
  final logFile = File(
    '${tempDir.path}${Platform.pathSeparator}${name}_update_log.txt',
  );
  if (await logFile.exists()) await logFile.delete();
  await logFile.create();

  logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      colors: stdout.supportsAnsiEscapes,
      lineLength: stdout.terminalColumns,
    ),
    output: MultiOutput([
      ConsoleOutput(),
      FileOutput(file: logFile),
    ]),
  );
}
