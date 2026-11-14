# Polo

A fast, clean file manager for Android with built-in tools, made with Flutter. Polo uses a warm orange and cream design with a light and dark theme.

> Status: early development (v0.4.0). Home, Browse, Search, Tools, Trash and Storage all work. More tools are on the way.

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

**Browse**
- Browse internal storage with a tappable breadcrumb path
- List or grid view (saved), with real picture previews for images
- Sort by name, date or size, and show or hide hidden files
- Multi-select with long-press, then copy, move, share, delete and a More menu (rename, details, compress to ZIP, extract, convert, make PDF)
- Create new folders
- Name conflicts never overwrite: pasting `photo.jpg` next to an existing one gives `photo (1).jpg`

**Search and categories**
- Search every file and folder by name, with filter chips
- Tap a category on Home or Storage to see all images, videos, audio, documents, archives or apps in one list

**Tools**
- Image converter: PNG and JPG, with adjustable JPG quality
- Images to PDF: reorder pages, A4 or fit-to-image, quality slider
- Zip and unzip: compress files and folders, extract `.zip` files into their own folder
- Duplicate finder: finds identical files by content and moves the extra copies to trash
- Originals are never touched: results are saved next to them

**Trash and details**
- Deleted files go to a trash you can restore from (Settings, then Trash), with Undo in Browse
- Items are removed for good after 30 days
- Details dialog for any file or folder: type, location, size and dates

**Storage**
- Usage bar split by file type, with file counts and sizes
- Largest files list for quick cleanup

**Design**
- Orange and cream light theme and warm charcoal dark theme (Material 3)
- Theme toggle: System, Light or Dark, saved between launches
- Custom app icon (themed icon on Android 13+) and a splash screen for both themes

**Planned**
- Video to audio
- WebP output for the image converter

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
    trash_service.dart           Trash: move, restore, delete forever, 30-day clean-up
    archive_service.dart         Create and extract ZIP files
    convert_service.dart         Image conversion (background isolate)
    pdf_service.dart             Images to PDF (background isolate)
    duplicate_finder.dart        Finds identical files by size and content hash
    storage_scanner.dart         Scans storage for the breakdown, largest, recent files and search index
    storage_controller.dart      Shares scan results between screens
    storage_info.dart            Total and free space, read through a platform channel
    storage_access.dart          Storage permission helper
    settings_controller.dart     Saved sort, hidden files and list/grid choice
  theme/
    app_theme.dart               Light and dark ThemeData
    theme_controller.dart        Theme mode state, saved with shared_preferences
  screens/
    home_shell.dart              Navigation bar and top-level screens
    home_screen.dart             Storage card, quick access, recent files
    browse_screen.dart           Browsing, selection and file actions
    search_screen.dart           Search with filters
    category_screen.dart         All files of one type
    tools_screen.dart            Tool cards and the zip menu
    convert_images_screen.dart   Image converter
    images_to_pdf_screen.dart    Images to PDF
    duplicates_screen.dart       Duplicate finder
    trash_screen.dart            Trash
    pick_files_screen.dart       In-app file picker used by tools
    storage_screen.dart          Breakdown and largest files
    settings_screen.dart         Theme, browsing options, trash, about
    about_screen.dart            Version, licenses and links
  widgets/                       File tile, grid tile, dialogs, details, open-file helper
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

- [shared_preferences](https://pub.dev/packages/shared_preferences): saves theme and browsing choices
- [permission_handler](https://pub.dev/packages/permission_handler): storage access
- [open_filex](https://pub.dev/packages/open_filex): opens files in other apps
- [share_plus](https://pub.dev/packages/share_plus): shares files
- [image](https://pub.dev/packages/image): image conversion
- [pdf](https://pub.dev/packages/pdf): builds PDFs
- [archive](https://pub.dev/packages/archive): ZIP files
- [crypto](https://pub.dev/packages/crypto): file hashing for the duplicate finder
- [package_info_plus](https://pub.dev/packages/package_info_plus): app version in About
- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) and [flutter_native_splash](https://pub.dev/packages/flutter_native_splash) (dev): icon and splash generation

## Roadmap

1. Theme, toggle and navigation shell (done)
2. Storage permission and folder browsing (done)
3. File actions: copy, move, rename, delete, share (done)
4. App icon and splash screen (done)
5. Home and Storage screens (done)
6. Tools: image converter, images to PDF, zip and unzip (done)
7. Search, categories, thumbnails (done)
8. Trash, file details, duplicate finder, grid view (done)
9. Video to audio, WebP output
10. Release prep: signing, store listing

## License

MIT. See the [LICENSE](LICENSE) file.