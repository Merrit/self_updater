import 'package:github/github.dart';

class GithubService {
  final GitHub github;
  final Repository repository;
  final RepositoriesService repoService;

  const GithubService._({
    required this.github,
    required this.repository,
    required this.repoService,
  });

  static Future<GithubService> initialize(String repoUrl) async {
    final github = GitHub();

    final repoParts = repoUrl.split('/');
    final owner = repoParts[repoParts.length - 2];
    final repoName = repoParts.last;

    final repo = await github.repositories.getRepository(
      RepositorySlug(owner, repoName),
    );

    return GithubService._(
      github: github,
      repository: repo,
      repoService: RepositoriesService(github),
    );
  }

  Future<List<Release>> getRecentReleases() async {
    return await repoService //
        .listReleases(repository.slug())
        .take(10)
        .toList();
  }
}
