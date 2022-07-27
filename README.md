<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages). 
-->

A self updater for Flutter apps

## Platform Support

| Linux | macOS | Windows |
| :---: | :---: | :-----: |
|   ✔️   |   ❌   |    ❌    |

Windows support coming *soon™*.

## Features

Automatically download the lastest release from GitHub releases for the running
platform, close the running app, update, relaunch app.

## Getting started

Add to `pubspec.yaml`

```yml
  self_updater:
    git:
      url: https://github.com/Merrit/self_updater.git
      ref: <commit hash>
```

## Usage

Basic example, this implementation would be better off in something like a
function elsewhere.

```dart
void main() {
    WidgetsFlutterBinding.ensureInitialized();

    // runApp()

    updateApp();
}

Future<void> updateApp() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    Updater updater = await Updater.initialize(
      currentVersion: packageInfo.version,
      updateChannel: UpdateChannel.stable,
      repoUrl: 'https://github.com/<user>/<repo>',
    );

    if (!updater.updateAvailable) return;

    String? updateArchivePath = await updater.downloadUpdate();
    if (updateArchivePath == null) {
      print('Downloading update was NOT successful.');
    } else {
      await updater.installUpdate(
        archivePath: updateArchivePath,
        relaunchApp: true,
      );
    }
}
```

## Additional information

Updater is only tested for Development releases so far.

The updater currently only supports updates from GitHub releases, that adhere to
Semver versioning as well as releases tagged `latest` for updating to
development releases. (Development releases currently require a file called
`BUILD` in the app directory with the UTC timestamp of when it was built.)

An in-development app that uses the updater can be seen here:
https://github.com/Merrit/adventure_list

This package has been created primarily for the author's needs, however if it is
found to be useful contributions, issues, ideas, etc are very welcome! 💙
