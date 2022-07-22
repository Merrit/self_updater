// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:github/src/common/model/repos_releases.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:self_updater/src/github_service.dart';
import 'package:self_updater/src/logs/logs.dart';
import 'package:version/version.dart';

enum ReleaseChannel {
  dev,
  beta,
  stable,
}

final _log = Logger('Updater');

class Updater {
  final String currentVersion;
  final ReleaseChannel releaseChannel;
  final String repoUrl;
  final List<Release> recentReleases;

  const Updater({
    required this.currentVersion,
    required this.releaseChannel,
    required this.repoUrl,
    required this.recentReleases,
  });

  static Future<Updater> initialize({
    required String currentVersion,
    required ReleaseChannel releaseChannel,
    required String repoUrl,
  }) async {
    initializeLogger();

    final github = await GithubService.initialize(repoUrl);

    return Updater(
      currentVersion: currentVersion,
      releaseChannel: releaseChannel,
      repoUrl: repoUrl,
      recentReleases: await github.getRecentReleases(),
    );
  }

  Release? latestDevVersion() =>
      recentReleases.firstWhereOrNull((element) => element.tagName == 'latest');

  // Untested
  Release? latestBetaVersion() => recentReleases
      .firstWhereOrNull((e) => e.tagName?.contains(RegExp(r'beta')) ?? false);

  // Untested
  Release? latestStableVersion() => recentReleases.firstWhereOrNull(
        (e) => e.tagName?.contains(RegExp(r'^((?!beta|alpha).)*$')) ?? false,
      );

  bool updateAvailable() {
    switch (releaseChannel) {
      case ReleaseChannel.dev:
        final latestDev = latestDevVersion()?.createdAt;
        if (latestDev == null) return false;
        return DateTime.parse(currentVersion).isBefore(latestDev);
      case ReleaseChannel.beta:
        final latestBeta = latestBetaVersion()?.tagName;
        if (latestBeta == null) return false;
        return Version.parse(currentVersion) <
            Version.parse(latestBeta.substring(1));
      case ReleaseChannel.stable:
        final latestStable = latestStableVersion()?.tagName;
        if (latestStable == null) return false;
        return Version.parse(currentVersion) <
            Version.parse(latestStable.substring(1));
    }
  }

  Release? get latestRelease {
    switch (releaseChannel) {
      case ReleaseChannel.dev:
        return latestDevVersion();
      case ReleaseChannel.beta:
        return latestBetaVersion();
      case ReleaseChannel.stable:
        return latestStableVersion();
    }
  }

  Future<void> downloadUpdate() async {
    // ignore: no_leading_underscores_for_local_identifiers
    final Release? _latestRelease = latestRelease;
    if (_latestRelease == null) return;

    ReleaseAsset? releaseAsset;

    switch (Platform.operatingSystem) {
      case 'linux':
        releaseAsset = _latestRelease //
            .assets
            ?.firstWhereOrNull((element) =>
                element.name?.contains(RegExp(r'-Linux-Portable.tar.gz')) ??
                false);
        break;
      default:
    }

    if (releaseAsset == null) return;
    if (releaseAsset.browserDownloadUrl == null) return;
    if (releaseAsset.name == null) return;

    final tempDir = await getTemporaryDirectory();
    final assetFullDownloadPath = '${tempDir.path}/${releaseAsset.name}';

    _log.info('Downloading asset');
    final dio = Dio();
    await dio.download(
      releaseAsset.browserDownloadUrl!,
      assetFullDownloadPath,
    );

    installUpdate(archivePath: assetFullDownloadPath);
  }

  Future<void> installUpdate({required String archivePath}) async {
    final String appDir = Directory.current.path;

    String executable = '';
    List<String> arguments = [];
    switch (Platform.operatingSystem) {
      case 'linux':
        executable = 'bash';
        arguments = ['-c', 'sleep 5 && tar -xf $archivePath -C $appDir'];
        break;
    }

    await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }
}
