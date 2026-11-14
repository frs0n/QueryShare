# QueryShare

An iPhone SFTP file server powered by [WorseQuery](https://github.com/forcequitOS/worse_query).

QueryShare has two screens: Connection and Logs. The interface uses an adaptive black-and-white palette and defaults to English.

## Connect

Keep your iPhone and computer on a reachable network, allow local network access, and start sharing. Copy the command shown in the app:

```sh
sftp -P 2222 mobile@IPHONE_IP
```

The default username is `mobile` and the default port is `2222`. A random password is generated once and stored in the device Keychain. Restarting the app keeps the saved password; manual changes are saved too. You can edit all three fields before starting the server.

Clients receive an English SSH authentication banner explaining the WorseQuery access method and virtual directories. The host key fingerprint is available in Logs.

## Browse files

Use original absolute paths under `/`, or browse the virtual container index:

| Directory | Contents |
| --- | --- |
| `/Containers/Apps` | Application data |
| `/Containers/Extensions` | Extension data |
| `/Containers/AppGroups` | Shared app containers |
| `/Containers/Daemons` | Internal daemon containers |
| `/Containers/SystemGroups` | System group containers |
| `/Containers/SystemData` | System data containers |

These directories map to real iOS paths. They are not copies: changes affect the original files. A category appears after containers have been discovered.

Supported operations include downloads, uploads, overwrites, random reads and writes, truncation, renaming, deletion, directory creation, symbolic links, and permission and timestamp changes. The server also supports the OpenSSH `posix-rename` and `fsync` extensions.

## Automatic discovery

The app restores its cached index, checks known directories, and tries to read the LaunchServices database. Its initial newest-first database search has a five-second budget. Missing the database does not stop discovery: container scanning continues automatically.

A file anywhere inside a container can reveal its UUID. Results are published as they are found. Refresh your client directory listing to see new entries. The refresh button in Logs updates the index.

Scanning uses the app data filesystem. A probe verifies that its inode and filesystem identifier resolve consistently. Progress is saved; completed ranges are not rescanned on every launch. Later passes check for newly created inode IDs. Active file requests take priority, and stopping sharing pauses discovery. Volume, OS build, and inode identity changes invalidate stale cache entries.

## Access and lifetime

QueryShare requests the maximum access WorseQuery can provide and does not enforce read-only sharing. A visible container does not guarantee every file is readable or writable: iOS permissions, data protection, and WorseQuery limitations still apply. This is not root access.

WorseQuery requires a usable signed App Group. QueryShare discovers available groups from its running signature. Without one, standard file access remains available and grant failures are logged. Access tokens use a 128-entry cache and are released when sharing stops.

The app prevents automatic screen locking while sharing in the foreground. Background execution is limited by iOS; sharing cannot remain available after the app is terminated. Up to eight SSH connections are accepted, with a five-minute read-idle timeout. The service supports SFTP, not an interactive shell, remote commands, or port forwarding.

## Build

Open `QueryShare.xcodeproj` in Xcode. Dependencies are resolved through SwiftPM and require network access on the first build. The deployment target is iOS 17; WorseQuery availability depends on the installed OS and effective App Group signature.

Use your existing signing configuration. English is the development language and the app's advertised localization. The app icon is provided by `qsicon.icon`.

## Tests

Run the portable core tests:

```sh
swift test
```

The repository also includes Objective-C database parser and inode scan fixtures, plus `Tests/sftp_integration.py` for an isolated local test server. Coverage includes password persistence logic, database parsing and truncated input, cache invalidation, scan progress, virtual path routing, authentication banners, and file operations.

Device arm64 Release and Simulator targets have been built successfully. Access to another app's known UUID path was verified over SFTP on a physical device. The latest automatic discovery and Keychain integration still require on-device validation; desktop fixtures do not establish success on every iOS version.

## License

GPL-3.0-or-later. See `LICENSE`. Original copyright and license notices remain in the source files.
