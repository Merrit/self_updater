// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:github/src/common/model/repos_releases.dart';
import 'package:helpers/helpers.dart';
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
  final Directory _tempDir;

  final String currentVersion;
  final UpdateChannel updateChannel;

  const Updater(
    this._recentReleases,
    this._tempDir, {
    required this.currentVersion,
    required this.updateChannel,
  });

  static Future<Updater> initialize({
    required String currentVersion,
    required UpdateChannel updateChannel,
    required String repoUrl,
  }) async {
    final github = await GithubService.initialize(repoUrl);

    await initializeLogger(github.repository.name);

    return Updater(
      await github.getRecentReleases(),
      await getTemporaryDirectory(),
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
      updateVersion = _latestRelease?.createdAt?.toUtc().toString();
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
      logger.e('No update release was found.');
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
      case 'windows':
        releaseAsset = localLatestRelease //
            .assets
            ?.firstWhereOrNull(
          (element) =>
              element.name?.contains(RegExp(r'-Windows-Portable.zip')) ?? false,
        );
        break;
    }

    if (releaseAsset == null ||
        releaseAsset.browserDownloadUrl == null ||
        releaseAsset.name == null) {
      logger.e(
        'ReleaseAsset from GitHub problem: ${releaseAsset?.toJson()}',
      );
      return null;
    }

    logger.i('tempDir: ${_tempDir.path}');
    final assetFullDownloadPath =
        '${_tempDir.path}${Platform.pathSeparator}${releaseAsset.name}';

    logger.i('Downloading asset');
    final dio = Dio();
    await dio.download(
      releaseAsset.browserDownloadUrl!,
      assetFullDownloadPath,
      deleteOnError: true,
      onReceiveProgress: (int count, int total) {
        String bytesLoaded = '$count';
        String totalSize = (total == -1) ? '???' : '$total';
        logger.i('Downloading release asset: $bytesLoaded/$totalSize');
      },
    );

    logger.i('Finished downloading release asset.');
    logger.i('Asset is located at: $assetFullDownloadPath');

    return assetFullDownloadPath;
  }

  Future<void> installUpdate({
    required String archivePath,
    required bool relaunchApp,
  }) async {
    if (!await File(archivePath).exists()) {
      throw Exception('No downloaded asset was found.');
    }

    logger.i(
      'Starting update. Local time: ${DateTime.now().toLocal().toString()}',
    );

    final String appDir = applicationDirectory.path;
    logger.i('Running app\'s directory: $appDir');

    String executable = '';
    List<String> arguments = [];
    switch (Platform.operatingSystem) {
      case 'linux':
        executable = 'bash';
        arguments = ['-c', 'sleep 5 && tar -xf "$archivePath" -C "$appDir"'];
        break;
      case 'windows':
        executable = 'powershell';
        // On Windows use `Stop-Process` to ensure the app has closed.
        arguments = [
          'Stop-Process -Id $pid -Force; Start-Sleep -Seconds 5; Expand-Archive -Force -LiteralPath "$archivePath" -DestinationPath "$appDir"'
        ];
        break;
    }

    if (relaunchApp) {
      switch (Platform.operatingSystem) {
        case 'linux':
          arguments[1] += ' && "${Platform.resolvedExecutable}" &';
          break;
        case 'windows':
          arguments[0] +=
              '; Start-Process -FilePath "${Platform.resolvedExecutable}" &';
          break;
      }
    }

    logger.i('''
Running command to extract update.
Executable: $executable
Arguments: $arguments

Exiting to allow update to continue.''');
    logger.close();

    await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }
}
