// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:github/src/common/model/repos_releases.dart';
import 'package:helpers/helpers.dart';
import 'package:intl/intl.dart';
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
      updateLogger.severe(
        'ReleaseAsset from GitHub problem: ${releaseAsset?.toJson()}',
      );
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    updateLogger.info('tempDir: ${tempDir.path}');
    final assetFullDownloadPath =
        '${tempDir.path}${Platform.pathSeparator}${releaseAsset.name}';

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

  /// Write installation logs to a file, as the calling application will end up
  /// being closed during the install and this file will be a way to debug or
  /// otherwise follow up on what happened during the update.
  void _logToFile() {
    // TODO: This log file should be elsewhere like /tmp or ~/.local/...
    final logFile = File(
      '${applicationDirectory.path}${Platform.pathSeparator}update_log.txt',
    );
    if (logFile.existsSync()) logFile.deleteSync();
    logFile.createSync();

    updateLogger.onRecord.listen((LogRecord record) {
      final String time = DateFormat('h:mm:ss a').format(record.time);

      var msg = 'SelfUpdater: ${record.level.name}: $time: '
          '${record.loggerName}: ${record.message}';

      if (record.error != null) msg += '\nError: ${record.error}';
      logFile.writeAsStringSync(
        '\n'
        '$msg'
        '\n',
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  Future<void> installUpdate({
    required String archivePath,
    required bool relaunchApp,
  }) async {
    if (!await File(archivePath).exists()) {
      throw Exception('No downloaded asset was found.');
    }

    _logToFile();
    updateLogger.info(
      'Starting update. Local time: ${DateTime.now().toLocal().toString()}',
    );

    final String appDir = applicationDirectory.path;
    updateLogger.info('Running app\'s directory: $appDir');

    String executable = '';
    List<String> arguments = [];
    switch (Platform.operatingSystem) {
      case 'linux':
        executable = 'bash';
        arguments = ['-c', 'sleep 5 && tar -xf "$archivePath" -C "$appDir"'];
        break;
      case 'windows':
        executable = 'powershell';
        arguments = [
          'Start-Sleep -Seconds 5; Expand-Archive -LiteralPath "$archivePath" -DestinationPath "$appDir"'
        ];
        break;
    }

    if (relaunchApp) {
      switch (Platform.operatingSystem) {
        case 'linux':
          arguments[1] += ' && "${Platform.resolvedExecutable}" &';
          break;
        case 'windows':
          arguments[1] +=
              '; Start-Process -FilePath "${Platform.resolvedExecutable}" &';
          break;
      }
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
