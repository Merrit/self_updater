import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

final Logger updateLogger = Logger.detached('SelfUpdater');

/// Print log messages.
void initializeLogger() {
  updateLogger.level = Level.ALL;

  updateLogger.onRecord.listen((record) {
    final String time = DateFormat('h:mm:ss a').format(record.time);

    var msg = 'SelfUpdater: ${record.level.name}: $time: '
        '${record.loggerName}: ${record.message}\n';

    if (record.error != null) msg += '\nError: ${record.error}';

    debugPrint(msg);
  });
}
