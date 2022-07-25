import 'package:flutter_test/flutter_test.dart';
import 'package:self_updater/src/updater.dart';

void main() {
  group('Updater:', () {
    test('recognizes available pre-release update', () async {
      final Updater updater = await Updater.initialize(
        currentVersion: '2022-07-23 16:36:59.425642',
        updateChannel: UpdateChannel.dev,
        repoUrl: 'https://github.com/Merrit/adventure_list',
      );

      expect(updater.updateAvailable, true);
    });
  });
}
