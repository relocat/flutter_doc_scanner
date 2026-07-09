# Vendored fork audit — `flutter_doc_scanner`

**Date:** 2026-07-10
**Upstream base commit:** `b6b22fe2e4d861c0df2ab182b417cccbe6ff7600`
(the fork's `main` was identical to upstream `main` at audit start)
**Auditor:** Relocat, for the Relocat zero-knowledge vault app.
**Purpose:** Harden this plugin for consumption as a git-pinned vendored fork (pinned by commit hash,
audited, upstream merges only via diff review). The plugin handles
plaintext page images before client-side encryption, so it is security-sensitive.

All line references are against the tree produced by this commit unless noted.

---

## 1. Security checklist

### 1.1 No network calls anywhere in Dart / Kotlin / Swift
**Verdict: PASS.**
Exhaustive search across `*.dart *.kt *.swift *.java *.cc *.cpp *.h *.m *.mm *.gradle *.podspec *.plist *.xml`
for `https?://`, `socket`, `okhttp`, `URLSession`, `URLConnection`, `URLRequest`, `dataTask`,
`download`, `retrofit`, `volley`, `package:dio`, `package:http`, `websocket`, `grpc`,
`firebase`, `HttpClient`, `InternetAddress`, `RawSocket`, `NSURLSession`, `CFNetwork`,
`XMLHttpRequest`, `fetch(` returned **no runtime network call sites**.
- Android plugin (`android/src/main/kotlin/.../FlutterDocScannerPlugin.kt`) only touches ML Kit
  (`GmsDocumentScanning`/`GmsDocumentScannerOptions`) and Flutter method-channel APIs.
- iOS plugin (`ios/.../SwiftFlutterDocScannerPlugin.swift`, `AutoScanViewController.swift`) only
  uses VisionKit / Vision / AVFoundation / PDFKit / UIKit — no networking frameworks.
- The only `http` string hits are documentation/metadata: `ios/flutter_doc_scanner.podspec:2,12,14`
  (cocoapods.org comment, `http://example.com` homepage placeholder, author Medium URL) — none are
  invoked at runtime.
- `android/src/main/AndroidManifest.xml` is empty (no `<uses-permission>`, no INTERNET, no network).
- Platform note (not a plugin network call): on Android the ML Kit **document-scanner module itself
  is downloaded on demand by Google Play services** at runtime the first time the scanner launches.
  This is a Play-services platform property, not a call made by this plugin's code.

### 1.2 No analytics / telemetry SDKs
**Verdict: PASS.**
No references to `analytics`, `crashlytics`, `firebase`, `sentry`, `amplitude`, `mixpanel`,
`segment`, `datadog`, or any telemetry SDK in source or in `pubspec.yaml` / `android/build.gradle`.
Runtime dependencies are only: `flutter`, `plugin_platform_interface` (Dart);
`play-services-mlkit-document-scanner` (Android); Flutter + system frameworks (iOS).

### 1.3 Output files written only inside the app sandbox
**Verdict: PASS (with an iOS location note for the app — see §2).**
- **Android:** the plugin writes **no files itself**. It returns the `content://` URIs produced by
  ML Kit (`page.getImageUri()` at `FlutterDocScannerPlugin.kt:201,207`; `pdf.getUri()` at
  `:183`). ML Kit stores results in the app's private storage and exposes them via a Play-services
  FileProvider — inside the app sandbox.
- **iOS:** the plugin writes into the app-sandbox **Documents** directory
  (`FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]`,
  `SwiftFlutterDocScannerPlugin.swift:79-83`). Exact paths in §2. All inside the sandbox.

### 1.4 ML Kit document-scanner Gradle artifact pinned to an explicit version
**Verdict: PASS (already pinned; no `+` range).**
`android/build.gradle` — `com.google.android.gms:play-services-mlkit-document-scanner:16.0.0`
(explicit version). AGP `8.6.0` and Kotlin `2.0.21` are likewise pinned; no dynamic version
ranges anywhere in the plugin's Gradle config. This audit added a comment documenting the pin
rationale; the version value is unchanged.

---

## 2. Per-platform output paths (for the app's scratch-dir design)

### Android
- The plugin returns **ML Kit `content://` URIs**, not filesystem paths, and controls no path.
  - Image pages: `GmsDocumentScanningResult.getPages()[i].getImageUri()` → JPEG content URIs
    (`FlutterDocScannerPlugin.kt:199-208`).
  - PDF: `GmsDocumentScanningResult.getPdf().getUri()` (`:178-184`).
- Backing store is the app's private cache/storage, surfaced through a Play-services FileProvider.
  **Implication:** on Android the app receives opaque `content://` URIs it must stream/copy out of
  (via `ContentResolver`), not paths under a directory the plugin owns.

### iOS
The plugin writes into `<app sandbox>/Documents/` (`getDocumentsDirectory()`,
`SwiftFlutterDocScannerPlugin.swift:79-83`). Filenames use a `yyyyMMdd-HHmmss` timestamp:
- Multi-page images (`getScannedDocumentAsImages`, standard path):
  `<Documents>/<timestamp>-<i>.png` (`saveScannedImages`, `:110-124`, write at `:119-120`).
- Single-picture fast path (`useAutomaticSinglePictureProcessing: true`):
  `<Documents>/<timestamp>-0.jpg` (`saveSingleImage`, `:85-97`, path at `:91`).
- PDF (`getScannedDocumentAsPdf`): `<Documents>/<timestamp>.pdf` (`saveScannedPdf`, `:126-148`,
  path at `:132`).

**Hardening note for the app (does NOT fail 1.3 — still in-sandbox):** iOS writes to
`Documents/`, which is a persistent, iCloud-backed and (if `UIFileSharingEnabled`/
`LSSupportsOpeningDocumentsInPlace` are set) Files-app-visible location — not a private
`Caches`/temp scratch dir. Plaintext page images therefore persist there until the app moves or
deletes them. The app must copy each result into its encrypted scratch pipeline and delete the
plugin's output immediately; it should not rely on the plugin cleaning up.

---

## 3. Capability checks (app depends on these)

### (a) Result format can be image-page URIs (NOT the platform-generated PDF), on BOTH platforms
**Verdict: PRESENT.**
Public Dart API (`lib/flutter_doc_scanner.dart`):

```dart
// Cross-platform image-page result (Android: content URIs; iOS: file paths). NOT PDF.
Future<ImageScanResult?> getScannedDocumentAsImages({
  int page = 4,
  ImageFormat imageFormat = ImageFormat.jpeg,
  double quality = 0.9,
  bool useAutomaticSinglePictureProcessing = false,
});                                             // flutter_doc_scanner.dart:38

// Android-only image-page URI variant (throws DocScanException UNSUPPORTED_PLATFORM elsewhere).
Future<ImageScanResult?> getScanDocumentsUri({int page = 4}); // flutter_doc_scanner.dart:82
```

Result carrier (`lib/flutter_doc_scanner_models.dart:14-42`):
```dart
class ImageScanResult { final List<String> images; int get count; }
```
`images` holds JPEG content URIs on Android / PNG(or single JPEG) file paths on iOS.
- Android native uses `RESULT_FORMAT_JPEG` for both `getScannedDocumentAsImages`
  (`FlutterDocScannerPlugin.kt:49-54`) and `getScanDocumentsUri` (`:61-66`), returning image URIs —
  never the PDF format for these calls.
- iOS `getScannedDocumentAsImages` returns a `List<String>` of image file paths
  (`SwiftFlutterDocScannerPlugin.swift:102-103,123`), not a PDF.

### (b) Android exposes a page-limit passthrough to ML Kit
**Verdict: PRESENT.**
`page` named parameter on every scan method → method-channel arg `'page'`
(`flutter_doc_scanner_method_channel.dart:24,45,64,80`) → Kotlin
`(arguments?.get("page") as? Int)?.coerceAtLeast(1) ?: DEFAULT_PAGE_LIMIT`
(`FlutterDocScannerPlugin.kt:88`) → `GmsDocumentScannerOptions.Builder().setPageLimit(pageLimit)`
(`:123`). Dart validates `page >= 1` (`flutter_doc_scanner.dart:97-101`).

### (c) Android exposes `isGalleryImport` configuration
**Verdict: PRESENT BUT COUPLED — flagged as a concern (see §6).**
The plugin does call ML Kit's `GmsDocumentScannerOptions.Builder().setGalleryImportAllowed(...)`
(`FlutterDocScannerPlugin.kt:122`). **There is no dedicated public Dart parameter** to set it.
It is reachable from the public API **only indirectly**, via `useAutomaticSinglePictureProcessing`
on `getScannedDocumentAsImages`:

```
fastSinglePageMode   = (requestCode == REQUEST_CODE_SCAN_IMAGES && useAutomaticSinglePictureProcessing)  // kt:92-93
galleryImportAllowed = !fastSinglePageMode                                                               // kt:100
```
- `useAutomaticSinglePictureProcessing: true`  → gallery import **disabled** (`setGalleryImportAllowed(false)`).
- `useAutomaticSinglePictureProcessing: false` (default) → gallery import **enabled**.
- For every other method (`getScanDocuments`, `getScannedDocumentAsPdf`, `getScanDocumentsUri`)
  `fastSinglePageMode` is always false, so gallery import is **hardcoded enabled**.

Enabling `useAutomaticSinglePictureProcessing` also forces single-page (`effectivePageLimit = 1`,
`kt:94`) and `SCANNER_MODE_BASE` (`kt:95-99`), and on iOS switches to an entirely different custom
capture controller. So "gallery import disabled" cannot be combined with multi-page scanning or with
the `getScanDocumentsUri` path. See §6.

---

## 4. Uprightness finding (are returned page JPEGs physically upright / EXIF orientation absent or =1?)

**Verdict: NO uniform plugin-level guarantee across output paths. Evidence-based per path:**

- **Android (`getScannedDocumentAsImages`, `getScanDocumentsUri`):** the plugin passes ML Kit's page
  image URIs through **unchanged** — no decode, re-encode, or EXIF handling
  (`FlutterDocScannerPlugin.kt:199-208`). Physical uprightness / EXIF orientation is entirely a
  property of ML Kit's output; the plugin neither enforces nor normalizes it. (ML Kit's
  document-scanner output is perspective-corrected and generally upright, but that is not guaranteed
  by any code in this fork.)
- **iOS standard image path (`saveScannedImages`):** writes **PNG** via `UIImage.pngData()`
  (`SwiftFlutterDocScannerPlugin.swift:110-124`, write at `:119-120`). PNG carries no EXIF
  orientation tag (so "EXIF absent" is trivially true), but physical uprightness depends on the
  `imageOrientation` of `VNDocumentCameraScan.imageOfPage(at:)`; VisionKit returns upright,
  perspective-corrected pages, yet the plugin performs **no explicit normalization** here. Note also
  that `imageFormat` and `quality` are **ignored** on this path — it always writes PNG.
- **iOS single-picture fast path (`saveSingleImage`):** writes JPEG via
  `image.jpegData(compressionQuality: 0.78)` (`:85-97`) **after** explicit upright normalization in
  `AutoScanViewController.prepareSingleImage` — `normalizedUprightImage` redraws any non-`.up`
  orientation into pixels (`AutoScanViewController.swift:295-304`) and `forcePortraitOrientation`
  rotates landscape to portrait (`:306-326`). The encoded `UIImage` is therefore `.up`, so the JPEG
  is physically upright with EXIF orientation = 1 (or absent). (The `quality` Dart arg is not used
  here either; 0.78 is hardcoded.)

**Conclusion:** only the iOS single-picture path provides an explicit upright guarantee. The Android
paths (the primary image-URI flow) are untouched pass-through, and the iOS standard path relies on
VisionKit's behavior without normalizing. The app's own orientation gate is therefore warranted and
should not assume EXIF=1/absent from the plugin.

---

## 5. Changes this fork makes vs upstream (`b6b22fe`)

All changes are in this single hardening commit; the fork otherwise matches upstream `b6b22fe`.

1. **Removed desktop/web plugin platform stubs** (dead code, smaller attack surface; keep
   android/ios only): deleted top-level `linux/`, `macos/`, `windows/` directories and
   `lib/flutter_doc_scanner_web.dart`.
2. **`pubspec.yaml`:** removed the `linux`, `macos`, `windows`, `web` entries under
   `flutter.plugin.platforms` (kept `android`, `ios`); removed the `flutter_web_plugins` dependency
   (was only used by the deleted web implementation); added a comment recording the audit rationale.
3. **Removed example desktop/web scaffolding** for consistency with android/ios-only support:
   deleted `example/linux/`, `example/macos/`, `example/windows/`, `example/web/`.
4. **`.metadata`:** trimmed the `migration.platforms` list to `root`, `android`, `ios` (dropped
   `linux`, `macos`, `web`, `windows`).
5. **`android/build.gradle`:** added a comment documenting that the ML Kit artifact is intentionally
   pinned (`16.0.0`, no `+` range) and must be bumped only via reviewed diff. Version value
   unchanged.
6. **Added `AUDIT.md`** (this file).

No changes were made to Dart public API, Android Kotlin, iOS Swift, or the ML Kit dependency version.

**Left in place intentionally:** `lib/flutter_doc_scanner_platform_check.dart` (`PlatformInfo`) is an
unused Dart-only helper that returns platform-name strings (including desktop names). It is not a
native platform stub and creates no channel/binding, so it was left untouched to avoid scope creep;
it is inert dead code.

---

## 6. Self-review findings & concerns

- **CONCERN (capability c coupling):** `isGalleryImport` is not an independent public Dart
  parameter. It can only be turned off by enabling `useAutomaticSinglePictureProcessing`, which
  simultaneously forces single-page + `SCANNER_MODE_BASE` (and a different iOS capture flow), and is
  unavailable on the `getScanDocumentsUri`/PDF paths (where gallery import is hardcoded enabled). If
  the app needs "multi-page, camera-only (no gallery import), image-URI" capture, that combination
  is **not expressible** with the current public API and would require adding a dedicated
  `isGalleryImport`/`galleryImportAllowed` parameter — i.e., unbudgeted fork API work. Not added
  here; surfaced for the maintainers to decide.
- **NOTE (iOS output location):** results land in `Documents/`, a backed-up / potentially
  Files-app-visible location rather than a private temp/`Caches` dir (§2). In-sandbox, so 1.3
  passes, but the app must evacuate and delete plaintext scans promptly, and a future fork change to
  write into `Caches`/temp would reduce plaintext-at-rest exposure.
- **NOTE (iOS `imageFormat`/`quality` ignored on standard path):** `getScannedDocumentAsImages`
  always writes PNG on the standard iOS path regardless of `imageFormat`, and the single-picture
  path hardcodes JPEG quality 0.78 regardless of `quality`. The Dart docs imply these are honored on
  iOS. Not a security issue; flagged for app-side expectations.
- Network / telemetry / sandbox / pinning checks all pass; desktop and web stubs removed; the plugin
  still declares only android + ios and requires no web-only dependency.
