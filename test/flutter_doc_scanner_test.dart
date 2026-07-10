import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner_platform_interface.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterDocScannerPlatform
    with MockPlatformInterfaceMixin
    implements FlutterDocScannerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<dynamic> getScanDocuments(int page) => Future.value();

  @override
  Future<dynamic> getScannedDocumentAsImages({
    required int page,
    required String imageFormat,
    required double quality,
    bool useAutomaticSinglePictureProcessing = false,
  }) => Future.value();

  @override
  Future<dynamic> getScannedDocumentAsPdf(int page) => Future.value();

  @override
  Future<dynamic> getScanDocumentsUri(int page) => Future.value();

  @override
  Future<bool> copyPageToFile({
    required String uri,
    required String destPath,
  }) => Future.value(true);
}

void main() {
  final FlutterDocScannerPlatform initialPlatform =
      FlutterDocScannerPlatform.instance;

  test('$MethodChannelFlutterDocScanner is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterDocScanner>());
  });

  test('getPlatformVersion', () async {
    FlutterDocScanner flutterDocScannerPlugin = FlutterDocScanner();
    MockFlutterDocScannerPlatform fakePlatform =
        MockFlutterDocScannerPlatform();
    FlutterDocScannerPlatform.instance = fakePlatform;

    expect(await flutterDocScannerPlugin.getPlatformVersion(), '42');
  });

  test('copyPageToFile delegates to the platform and returns its result',
      () async {
    FlutterDocScanner flutterDocScannerPlugin = FlutterDocScanner();
    MockFlutterDocScannerPlatform fakePlatform =
        MockFlutterDocScannerPlatform();
    FlutterDocScannerPlatform.instance = fakePlatform;

    expect(
      await flutterDocScannerPlugin.copyPageToFile(
        uri: 'content://example/page-0',
        destPath: '/tmp/page-0.jpg',
      ),
      isTrue,
    );
  });
}
