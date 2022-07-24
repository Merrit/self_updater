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

enum UpdateChannel {
  stable,
  beta,
  dev,
}

class Updater {
  final List<Release> _recentReleases;

  final String currentVersion;
  final UpdateChannel updateChannel;

  const Updater(
    this._recentReleases, {
    required this.currentVersion,
    required this.updateChannel,
  });

  static Future<Updater> initialize({
    required String currentVersion,
    required UpdateChannel updateChannel,
    required String repoUrl,
  }) async {
    initializeLogger();

    final github = await GithubService.initialize(repoUrl);

    return Updater(
      await github.getRecentReleases(),
      currentVersion: currentVersion,
      updateChannel: updateChannel,
    );
  }

  bool get updateAvailable {
    switch (updateChannel) {
      case UpdateChannel.dev:
        final latestDev = _latestDevVersion?.createdAt;
        if (latestDev == null) return false;
        final current = DateTime.tryParse(currentVersion) ?? DateTime(1965);
        return current.isBefore(latestDev);
      case UpdateChannel.beta:
        final latestBeta = _latestBetaVersion?.tagName;
        if (latestBeta == null) return false;
        return Version.parse(currentVersion) <
            Version.parse(latestBeta.substring(1));
      case UpdateChannel.stable:
        final latestStable = _latestStableVersion?.tagName;
        if (latestStable == null) return false;
        return Version.parse(currentVersion) <
            Version.parse(latestStable.substring(1));
    }
  }

  String? get updateVersion {
    String? updateVersion;
    if (_latestRelease?.tagName == 'latest' &&
        updateChannel == UpdateChannel.dev) {
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
    switch (updateChannel) {
      case UpdateChannel.dev:
        return _latestDevVersion;
      case UpdateChannel.beta:
        return _latestBetaVersion;
      case UpdateChannel.stable:
        return _latestStableVersion;
    }
  }

  /// If successful returns the path to the downloaded update file.
  Future<String?> downloadUpdate() async {
    // ignore: no_leading_underscores_for_local_identifiers
    final Release? localLatestRelease = _latestRelease;
    if (localLatestRelease == null) {
      updateLogger.severe('No update release was found.');
      return null;
    }

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

    if (releaseAsset == null ||
        releaseAsset.browserDownloadUrl == null ||
        releaseAsset.name == null) {
      updateLogger.severe(
        'ReleaseAsset from GitHub problem: ${releaseAsset?.toJson()}',
      );
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    updateLogger.info('tempDir: ${tempDir.path}');
    final assetFullDownloadPath = '${tempDir.path}/${releaseAsset.name}';

    updateLogger.info('Downloading asset');
    final dio = Dio();
    await dio.download(
      releaseAsset.browserDownloadUrl!,
      assetFullDownloadPath,
      deleteOnError: true,
      onReceiveProgress: (int count, int total) {
        String bytesLoaded = '$count';
        String totalSize = (total == -1) ? '???' : '$total';
        updateLogger.info('Downloading release asset: $bytesLoaded/$totalSize');
      },
    );

    updateLogger.info('Finished downloading release asset.');
    updateLogger.info('Asset is located at: $assetFullDownloadPath');

    return assetFullDownloadPath;
  }

  Future<void> installUpdate({required String archivePath}) async {
    if (!await File(archivePath).exists()) {
      throw Exception('No downloaded asset was found.');
    }

    final String appDir = Directory.current.path;
    updateLogger.info('Running app\'s directory: $appDir');

    String executable = '';
    List<String> arguments = [];
    switch (Platform.operatingSystem) {
      case 'linux':
        executable = 'bash';
        arguments = ['-c', 'sleep 5 && tar -xf "$archivePath" -C "$appDir"'];
        break;
    }

    updateLogger.info('''
Running command to extract update.
Executable: $executable
Arguments: $arguments''');

    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );

    updateLogger.info(
      'Extraction started as detached process with PID ${process.pid}',
    );
    updateLogger.info('Exiting to allow update to continue.');

    exit(0);
  }
}
