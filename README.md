# Polo

A fast, clean file manager for Android, built with Flutter. Polo uses a warm orange and cream design with a light and dark theme.

> Status: early development. You can browse your files and manage them. Home, Starred and Storage screens are next.

## Features

**Available now**
- Browse internal storage with a tappable breadcrumb path
- Folders first, then files, with a colored icon per file type
- Sort by name, date or size, and show or hide hidden files
- Open files in the app of your choice
- Multi-select with long-press, plus Select all
- Copy, move, rename, delete and share
- Create new folders
- Name conflicts never overwrite: pasting `photo.jpg` next to an existing one gives `photo (1).jpg`
- Orange and cream light theme and warm charcoal dark theme (Material 3)
- Theme toggle: System, Light or Dark, saved between launches
- Custom app icon (with a themed icon on Android 13+) and a splash screen for both themes

**Planned**
- Home screen with a storage summary, categories and recent files
- Starred files and folders
- Storage breakdown by file type, large files and duplicates
- Search
- List and grid view toggle
- SD card support

## App details

| | |
|---|---|
| App name | Polo |
| Package | `cos.aos.polo` |
| Platform | Android |
| Framework | Flutter (Material 3) |

## Permissions

Polo asks for **All files access** (`MANAGE_EXTERNAL_STORAGE`) the first time you open Browse, because a file manager needs to see every folder. On Android 12 and older it uses the standard storage permission instead. Nothing leaves your device.

## Project structure

```
lib/
  main.dart                    App entry point and theme wiring
  models/
    file_item.dart             File or folder data, type detection, size and date labels
  services/
    file_service.dart          Listing, copy, move, rename, delete, new folder
  theme/
    app_theme.dart             Light and dark ThemeData
    theme_controller.dart      Theme mode state, saved with shared_preferences
  screens/
    home_shell.dart            Navigation bar and top-level screens
    browse_screen.dart         Browsing, selection and file actions
    settings_screen.dart       Theme selector
  widgets/
    file_tile.dart             A single file or folder row
assets/icon/                   App icon and splash images
```

## Getting started

Requirements: Flutter SDK, Android Studio (or the Android SDK) and an Android device or emulator.

```bash
git clone https://github.com/ashwithfrank/polo.git
cd polo
flutter pub get
flutter run
```

To regenerate the launcher icon and splash screen after changing the images in `assets/icon/`:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### Build troubleshooting (Windows)

If the project is on a different drive from the Flutter pub cache, Gradle can fail with `this and base files have different roots`. Add this line to `android/gradle.properties`:

```
kotlin.incremental=false
```

Then run `flutter clean` and build again. Alternatively, set the `PUB_CACHE` environment variable to a folder on the same drive as the project.

## Dependencies

- [shared_preferences](https://pub.dev/packages/shared_preferences): saves the theme choice
- [permission_handler](https://pub.dev/packages/permission_handler): storage access
- [open_filex](https://pub.dev/packages/open_filex): opens files in other apps
- [share_plus](https://pub.dev/packages/share_plus): shares files
- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) and [flutter_native_splash](https://pub.dev/packages/flutter_native_splash) (dev): icon and splash generation

## Roadmap

1. Theme, toggle and navigation shell (done)
2. Storage permission and folder browsing (done)
3. File actions: copy, move, rename, delete, share (done)
4. App icon and splash screen (done)
5. Home, Starred and Storage screens
6. Search, grid view and polish

## License

No license has been chosen yet. Add a `LICENSE` file before sharing the code publicly.
