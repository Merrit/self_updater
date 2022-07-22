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
  final List<Release> _recentReleases;

  final String currentVersion;
  final ReleaseChannel releaseChannel;

  const Updater(
    this._recentReleases, {
    required this.currentVersion,
    required this.releaseChannel,
  });

  static Future<Updater> initialize({
    required String currentVersion,
    required ReleaseChannel releaseChannel,
    required String repoUrl,
  }) async {
    initializeLogger();

    final github = await GithubService.initialize(repoUrl);

    return Updater(
      await github.getRecentReleases(),
      currentVersion: currentVersion,
      releaseChannel: releaseChannel,
    );
  }

  bool get updateAvailable {
    switch (releaseChannel) {
      case ReleaseChannel.dev:
        final latestDev = _latestDevVersion?.createdAt;
        if (latestDev == null) return false;
        final current = DateTime.tryParse(currentVersion) ?? DateTime(1965);
        return current.isBefore(latestDev);
      case ReleaseChannel.beta:
        final latestBeta = _latestBetaVersion?.tagName;
        if (latestBeta == null) return false;
        return Version.parse(currentVersion) <
            Version.parse(latestBeta.substring(1));
      case ReleaseChannel.stable:
        final latestStable = _latestStableVersion?.tagName;
        if (latestStable == null) return false;
        return Version.parse(currentVersion) <
            Version.parse(latestStable.substring(1));
    }
  }

  String? get updateVersion {
    String? updateVersion;
    if (_latestRelease?.tagName == 'latest' &&
        releaseChannel == ReleaseChannel.dev) {
      final creationDate = _latestRelease?.createdAt?.toLocal();

      updateVersion =
          '${creationDate?.year}-${creationDate?.month}-${creationDate?.day}';
    } else {
      updateVersion = _latestRelease?.tagName;
    }

    return updateVersion;
  }

  Release? get _latestDevVersion => _recentReleases
      .firstWhereOrNull((element) => element.tagName == 'latest');

  // Untested
  Release? get _latestBetaVersion => _recentReleases
      .firstWhereOrNull((e) => e.tagName?.contains(RegExp(r'beta')) ?? false);

  // Untested
  Release? get _latestStableVersion => _recentReleases.firstWhereOrNull(
        (e) =>
            e.tagName?.contains(RegExp(r'^((?!beta|alpha|latest).)*$')) ??
            false,
      );

  Release? get _latestRelease {
    switch (releaseChannel) {
      case ReleaseChannel.dev:
        return _latestDevVersion;
      case ReleaseChannel.beta:
        return _latestBetaVersion;
      case ReleaseChannel.stable:
        return _latestStableVersion;
    }
  }

  Future<void> downloadUpdate() async {
    // ignore: no_leading_underscores_for_local_identifiers
    final Release? localLatestRelease = _latestRelease;
    if (localLatestRelease == null) return;

    ReleaseAsset? releaseAsset;

    switch (Platform.operatingSystem) {
      case 'linux':
        releaseAsset = localLatestRelease //
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
