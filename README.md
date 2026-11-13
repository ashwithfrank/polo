# Polo

A fast, clean file manager for Android with built-in tools, made with Flutter. Polo uses a warm orange and cream design with a light and dark theme.

> Status: early development. Home, Browse, Tools and Storage all work. More tools are on the way.

## Features

**Home**
- Storage summary: used, free and total space
- Quick access to Downloads, Camera, Pictures, Documents, Music and Movies
- Your most recent files

**Browse**
- Browse internal storage with a tappable breadcrumb path
- Folders first, with a colored icon per file type
- Sort by name, date or size, and show or hide hidden files
- Multi-select with long-press, then copy, move, rename, delete and share
- Create new folders
- Name conflicts never overwrite: pasting `photo.jpg` next to an existing one gives `photo (1).jpg`

**Tools**
- Image converter: PNG and JPG, with adjustable JPG quality
- Convert from the Tools tab, or select images in Browse and tap Convert
- Originals are never touched: the converted file is saved next to them

**Storage**
- Usage bar split by file type, with file counts and sizes
- Largest files list with a delete button for quick cleanup

**Design**
- Orange and cream light theme and warm charcoal dark theme (Material 3)
- Theme toggle: System, Light or Dark, saved between launches
- Custom app icon (themed icon on Android 13+) and a splash screen for both themes

**Planned**
- More tools: images to PDF, zip and unzip, video to audio
- Search
- Duplicate file finder
- List and grid view toggle
- SD card support

## App details

| | |
|---|---|
| App name | Polo |
| Package | `com.aos.polo` |
| Platform | Android |
| Framework | Flutter (Material 3) |
| Made by | AlphaOmega Studio |

## Permissions

Polo asks for **All files access** (`MANAGE_EXTERNAL_STORAGE`) the first time you open it, because a file manager needs to see every folder. On Android 12 and older it uses the standard storage permission instead. Nothing leaves your device.

## Project structure

```
lib/
  main.dart                      App entry point and theme wiring
  models/
    file_item.dart               File or folder data, type detection, size and date labels
    storage_category.dart        File type groups used by the Storage screen
  services/
    file_service.dart            Listing, copy, move, rename, delete, new folder
    convert_service.dart         Image conversion (runs in a background isolate)
    storage_scanner.dart         Scans storage for the breakdown, largest and recent files
    storage_controller.dart      Shares scan results between Home and Storage
    storage_info.dart            Total and free space, read through a platform channel
    storage_access.dart          Storage permission helper
  theme/
    app_theme.dart               Light and dark ThemeData
    theme_controller.dart        Theme mode state, saved with shared_preferences
  screens/
    home_shell.dart              Navigation bar and top-level screens
    home_screen.dart             Storage card, quick access, recent files
    browse_screen.dart           Browsing, selection and file actions
    tools_screen.dart            Tool cards
    convert_images_screen.dart   Image converter
    pick_files_screen.dart       In-app file picker used by tools
    storage_screen.dart          Breakdown and largest files
    settings_screen.dart         Theme selector
  widgets/                       File tile, message view, open-file helper
  utils/format.dart              Size formatting
assets/icon/                     App icon and splash images
android/.../MainActivity.kt      Storage info platform channel
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
- [image](https://pub.dev/packages/image): image conversion
- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) and [flutter_native_splash](https://pub.dev/packages/flutter_native_splash) (dev): icon and splash generation

## Roadmap

1. Theme, toggle and navigation shell (done)
2. Storage permission and folder browsing (done)
3. File actions: copy, move, rename, delete, share (done)
4. App icon and splash screen (done)
5. Home and Storage screens (done)
6. Tools: image converter (done)
7. More tools: images to PDF, zip and unzip, video to audio
8. Search, duplicate finder, grid view and polish

## License

No license has been chosen yet. Add a `LICENSE` file before sharing the code publicly.