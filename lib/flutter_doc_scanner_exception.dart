/// Exception thrown by the FlutterDocScanner plugin.
class DocScanException implements Exception {
  /// Machine-readable error code.
  final String code;

  /// Human-readable description of the error.
  final String message;

  /// Optional platform-specific details.
  final dynamic details;

  const DocScanException({
    required this.code,
    required this.message,
    this.details,
  });

  /// The scanner requires a foreground activity (Android).
  static const codeNoActivity = 'NO_ACTIVITY';

  /// Another scan is already in progress.
  static const codeScanInProgress = 'SCAN_IN_PROGRESS';

  /// The scan operation failed.
  static const codeScanFailed = 'SCAN_FAILED';

  /// PDF creation failed (iOS).
  static const codePdfCreationError = 'PDF_CREATION_ERROR';

  /// The user cancelled the scan.
  static const codeCancelled = 'CANCELLED';

  /// The platform does not support this feature.
  static const codeUnsupported = 'UNSUPPORTED_PLATFORM';

  /// Camera access was denied or restricted (iOS pre-flight check).
  ///
  /// Raised by the scan methods before the camera controller is presented when
  /// `AVCaptureDevice.authorizationStatus(for: .video)` is `.denied` or
  /// `.restricted`. The app should surface a rationale and deep-link to Settings.
  static const codePermissionDenied = 'PERMISSION_DENIED';

  /// Copying a scanned page out of a content URI failed (Android only).
  ///
  /// Raised by `copyPageToFile` on a null input stream, IO error, or lapsed URI
  /// permission grant. The message is static and never contains the URI or path.
  static const codeCopyFailed = 'COPY_FAILED';

  @override
  String toString() => 'DocScanException($code): $message';
}
