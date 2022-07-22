import 'package:flutter_test/flutter_test.dart';
import 'package:self_updater/src/github_service.dart';

Future<void> main() async {
  final github = await GithubService.initialize(
    'https://github.com/Merrit/adventure_list',
  );

  group('GithubService:', () {
    test('parses url correctly', () {
      expect(github.repository.name, 'adventure_list');
    });

    // test('?!!?', () async {
    //   final releases = await github.getRecentReleases();
    // });
  });
}
