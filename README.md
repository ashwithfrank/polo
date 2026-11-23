# Polo

An offline file manager and toolbox for Android, made with Flutter by [AlphaOmega Studio](https://github.com/ashwithfrank).

Package: `com.aos.polo` · Version: 1.8.0 · Android only

Polo browses your files and ships with the tools people usually need a separate app for: convert, compress, scan, read text from pictures, work with PDFs, trim audio and video, protect PDFs and ZIPs with passwords, and keep private files locked. Everything runs on your phone. There is no internet permission, no account, no ads and no analytics.

## Features

### Browse and organize
- Browse folders with breadcrumbs, list or grid view, sorting, and hidden files (optional)
- Copy, move, rename, delete (with a 30 day Trash), share, create folders, conflict-safe paste
- Hold a file, then slide up or down to select many at once; set the hold time in Settings
- Quick Actions (⋮ menu) on every file, with actions that fit the file type
- Batch rename with live preview, zip and unzip (including password-protected ZIPs), duplicate finder
- Search by name and browse by type (images, videos, audio, documents, archives, apps)
- Favourites (star any file or folder) and Recently opened on Home
- Inspector (details, checksums, metadata) and file compare
- Open with Polo and Share to Polo from other apps, and pick files from Polo for other apps
- Storage screen with a usage breakdown and the largest files

### Tools
- **Convert and compress:** images (PNG, JPG, WebP and more) with before/after preview and sharing presets, video compress, audio to M4A, video to audio, trim audio and video, photo collage
- **Images:** edit, resize, strip metadata and location, photo info, images to PDF
- **PDF:** reader with search and night mode, merge, split, organize pages, PDF to images (whole pages, or the pictures inside at their original size), text to PDF, watermark, page numbers (with preview), lock and unlock with a password, scanned PDF to text
- **Scan and create:** QR scanner and generator, text from a picture (OCR, Latin and Devanagari), document scanner
- **Clean up:** large files, duplicates, empty folders
- **Developer and text:** APK analyzer, checksums, encoders and formatters, password generator, text editor, word count, find and replace across files
- **Vault:** password-locked private files (PBKDF2 and AES-256-GCM). A forgotten password cannot be recovered.

### Look and feel
- Orange and cream Material 3 design with light, dark and True black themes
- Accent colours, customizable Home (reorder or hide sections), quick-access folders
- Settings for where tools save results (next to the original or in a Polo folder), vibration (with strength), and animations

## Where results are saved
By default, edits stay next to the original file. Things made from scratch (scans, QR codes, text read from a picture) go to the `Polo` folder, in `Images`, `Documents`, `Scans`, `QR codes`, `Archives` or `Media`. You can change this in Settings.

## Permissions
- **All files access** (`MANAGE_EXTERNAL_STORAGE`) on Android 11 and newer, or the standard storage permission on Android 10 and older. Needed to be a file manager.
- **Camera**, only when you use the QR scanner, text from a picture, or the document scanner.
- **Vibration**, a normal permission for tap feedback.
- No internet permission.

## Privacy
See [PRIVACY.md](PRIVACY.md). Polo works on your device only. Nothing is uploaded, and no personal data is collected.

## Build it
1. Install Flutter and the Android toolchain.
2. `flutter pub get`
3. `flutter run` on an Android device or emulator

Some features use native Android code (video and audio conversion, PDF passwords, APK analysis, Open with). Use a full `flutter run`, not hot reload, after changing anything in `android/`.

## Credits
Built with Flutter and a handful of open-source packages, including pdfrx, Google ML Kit (text recognition and document scanner), AndroidX Media3 and PdfBox-Android.

## License
See [LICENSE](LICENSE).
