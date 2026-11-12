# Polo

A fast, clean file manager for Android, built with Flutter. Polo uses a warm orange and cream design with a light and dark theme.

> Status: early development. The theme, theme toggle and app shell are done. File browsing is next.

## Features

**Available now**
- Orange and cream light theme and warm charcoal dark theme (Material 3)
- Theme toggle: System, Light or Dark, saved between launches
- Bottom navigation: Home, Browse, Starred, Storage
- Settings screen

**Planned**
- Browse folders with breadcrumbs, list and grid views, and sorting
- Open, copy, move, rename, delete and share files
- Multi-select with a bottom action bar
- Starred files and folders
- Storage breakdown by file type, large files and duplicates
- Search

## App details

| | |
|---|---|
| App name | Polo |
| Package | `cos.aos.polo` |
| Platform | Android |
| Framework | Flutter (Material 3) |

## Project structure

```
lib/
  main.dart                  App entry point and theme wiring
  theme/
    app_theme.dart           Light and dark ThemeData
    theme_controller.dart    Theme mode state, saved with shared_preferences
  screens/
    home_shell.dart          Navigation bar and top-level screens
    settings_screen.dart     Theme selector
```

## Getting started

Requirements: Flutter SDK, Android Studio (or the Android SDK) and an Android device or emulator.

```bash
git clone <your-repo-url>
cd polo
flutter pub get
flutter run
```

### Build troubleshooting (Windows)

If the project is on a different drive from the Flutter pub cache, Gradle can fail with `this and base files have different roots`. Add this line to `android/gradle.properties`:

```
kotlin.incremental=false
```

Then run `flutter clean` and build again. Alternatively, set the `PUB_CACHE` environment variable to a folder on the same drive as the project.

## Dependencies

- [shared_preferences](https://pub.dev/packages/shared_preferences) for saving the theme choice

## Roadmap

1. Theme, toggle and navigation shell (done)
2. Storage permission and folder browsing
3. File actions: copy, move, rename, delete, share
4. Home, Starred and Storage screens
5. Polish: animations, empty states, app icon

## License

No license has been chosen yet. Add a `LICENSE` file before sharing the code publicly.