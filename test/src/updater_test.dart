import 'package:flutter_test/flutter_test.dart';
import 'package:self_updater/src/updater.dart';

void main() {
  group('Updater:', () {
    test('?!?!', () async {
      final Updater updater = await Updater.initialize(
        currentVersion:
            DateTime.now().subtract(const Duration(days: 1)).toString(),
        releaseChannel: ReleaseChannel.dev,
        repoUrl: 'https://github.com/Merrit/adventure_list',
      );

      await updater.downloadUpdate();
    });
  });
}
