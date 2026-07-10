import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner_exception.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterDocScanner platform = MethodChannelFlutterDocScanner();
  const MethodChannel channel = MethodChannel('flutter_doc_scanner');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('copyPageToFile returns true when the native side succeeds', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        expect(methodCall.method, 'copyPageToFile');
        expect(methodCall.arguments['uri'], 'content://example/page-0');
        expect(methodCall.arguments['destPath'], '/tmp/page-0.jpg');
        return true;
      },
    );

    expect(
      await platform.copyPageToFile(
        uri: 'content://example/page-0',
        destPath: '/tmp/page-0.jpg',
      ),
      isTrue,
    );
  });

  test('copyPageToFile maps a COPY_FAILED PlatformException to DocScanException',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        throw PlatformException(
          code: DocScanException.codeCopyFailed,
          message: 'Failed to copy scanned page.',
        );
      },
    );

    expect(
      () => platform.copyPageToFile(
        uri: 'content://example/page-0',
        destPath: '/tmp/page-0.jpg',
      ),
      throwsA(
        isA<DocScanException>().having(
          (e) => e.code,
          'code',
          DocScanException.codeCopyFailed,
        ),
      ),
    );
  });
}
