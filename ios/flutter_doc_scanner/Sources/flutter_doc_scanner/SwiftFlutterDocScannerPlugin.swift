import AVFoundation
import Flutter
import UIKit
import Vision
import VisionKit
import PDFKit

@available(iOS 13.0, *)
public class SwiftFlutterDocScannerPlugin: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
   var resultChannel: FlutterResult?
   var presentingController: VNDocumentCameraViewController?
   var currentMethod: String?

   public static func register(with registrar: FlutterPluginRegistrar) {
       let channel = FlutterMethodChannel(name: "flutter_doc_scanner", binaryMessenger: registrar.messenger())
       let instance = SwiftFlutterDocScannerPlugin()
       registrar.addMethodCallDelegate(instance, channel: channel)
   }

   /// Method names that present a camera-backed scanner. Each requires camera
   /// access, so they are gated by `cameraAuthorizationDenied()` below.
   private static let scanMethods: Set<String> = [
       "getScanDocuments",
       "getScannedDocumentAsImages",
       "getScannedDocumentAsPdf",
   ]

   /// Returns `true` when camera access has been explicitly denied or restricted
   /// (parental controls / MDM). `.authorized` and `.notDetermined` return
   /// `false` so the scanner still presents and the system prompt (on
   /// `.notDetermined`) or VisionKit handles the flow as before. The message is
   /// static and carries no details.
   private func cameraAuthorizationDenied() -> Bool {
       switch AVCaptureDevice.authorizationStatus(for: .video) {
       case .denied, .restricted:
           return true
       case .authorized, .notDetermined:
           return false
       @unknown default:
           return false
       }
   }

   public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
       if SwiftFlutterDocScannerPlugin.scanMethods.contains(call.method),
          cameraAuthorizationDenied() {
           result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission denied", details: nil))
           return
       }
       if SwiftFlutterDocScannerPlugin.scanMethods.contains(call.method),
          resultChannel != nil {
           result(FlutterError(code: "SCAN_IN_PROGRESS", message: "a scan is already in progress", details: nil))
           return
       }
       if call.method == "getScanDocuments" {
           let presentedVC: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
           if presentedVC == nil {
               result(FlutterError(code: "NO_PRESENTER", message: "no view controller to present the scanner", details: nil))
               return
           }
           self.resultChannel = result
           self.currentMethod = call.method
           self.presentingController = VNDocumentCameraViewController()
           self.presentingController!.delegate = self
           presentedVC?.present(self.presentingController!, animated: true)
       } else if call.method == "getScannedDocumentAsImages" {
           let presentedVC: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
           if presentedVC == nil {
               result(FlutterError(code: "NO_PRESENTER", message: "no view controller to present the scanner", details: nil))
               return
           }
           self.resultChannel = result
           self.currentMethod = call.method
           let arguments = call.arguments as? [String: Any]
           let useAutomaticSinglePictureProcessing =
               (arguments?["useAutomaticSinglePictureProcessing"] as? Bool) ?? false

           if useAutomaticSinglePictureProcessing {
               // New fast path: capture one picture and return immediately without review UI.
               let controller = AutoScanViewController()
               controller.modalPresentationStyle = .fullScreen
               controller.onImageCaptured = { [weak self] image in
                   guard let self = self else { return }
                   DispatchQueue.global(qos: .userInitiated).async {
                       do {
                           let path = try self.saveSingleImage(image: image)
                           DispatchQueue.main.async {
                               self.resultChannel?([path])
                               self.resultChannel = nil
                           }
                       } catch {
                           DispatchQueue.main.async {
                               self.resultChannel?(FlutterError(code: "SCAN_SAVE_ERROR", message: "Failed to save captured image", details: nil))
                               self.resultChannel = nil
                           }
                       }
                   }
               }
               controller.onCancel = { [weak self] in
                   self?.resultChannel?(nil)
                   self?.resultChannel = nil
               }
               controller.onError = { [weak self] error in
                   self?.resultChannel?(FlutterError(code: "SCAN_ERROR", message: "Failed to scan documents", details: nil))
                   self?.resultChannel = nil
               }
               presentedVC?.present(controller, animated: true)
           } else {
               self.presentingController = VNDocumentCameraViewController()
               self.presentingController!.delegate = self
               presentedVC?.present(self.presentingController!, animated: true)
           }
       } else if call.method == "getScannedDocumentAsPdf" {
           let presentedVC: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
           if presentedVC == nil {
               result(FlutterError(code: "NO_PRESENTER", message: "no view controller to present the scanner", details: nil))
               return
           }
           self.resultChannel = result
           self.currentMethod = call.method
           self.presentingController = VNDocumentCameraViewController()
           self.presentingController!.delegate = self
           presentedVC?.present(self.presentingController!, animated: true)
       } else {
           result(FlutterMethodNotImplemented)
           return
       }
   }

   func getDocumentsDirectory() -> URL {
       let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
       let documentsDirectory = paths[0]
       return documentsDirectory
   }

   private func saveSingleImage(image: UIImage) throws -> String {
       let tempDirPath = getDocumentsDirectory()
       let currentDateTime = Date()
       let df = DateFormatter()
       df.dateFormat = "yyyyMMdd-HHmmss"
       let formattedDate = df.string(from: currentDateTime)
       let imagePath = tempDirPath.appendingPathComponent(formattedDate + "-0.jpg")
       guard let data = image.jpegData(compressionQuality: 0.78) else {
           throw NSError(domain: "flutter_doc_scanner", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Unable to encode JPEG data."])
       }
       try data.write(to: imagePath, options: .atomic)
       return imagePath.path
   }

   public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
       if currentMethod == "getScanDocuments" {
           saveScannedImages(scan: scan) // Uses existing logic
       } else if currentMethod == "getScannedDocumentAsImages" {
           saveScannedImages(scan: scan)
       } else if currentMethod == "getScannedDocumentAsPdf" {
           saveScannedPdf(scan: scan)
       }
       presentingController?.dismiss(animated: true)
   }

   private func saveScannedImages(scan: VNDocumentCameraScan) {
       let tempDirPath = getDocumentsDirectory()
       let currentDateTime = Date()
       let df = DateFormatter()
       df.dateFormat = "yyyyMMdd-HHmmss"
       let formattedDate = df.string(from: currentDateTime)
       var filenames: [String] = []
       for i in 0 ..< scan.pageCount {
           let page = scan.imageOfPage(at: i)
           let url = tempDirPath.appendingPathComponent(formattedDate + "-\(i).png")
           guard let data = page.pngData() else {
               resultChannel?(FlutterError(code: "SCAN_SAVE_ERROR", message: "failed to write a scanned page", details: nil))
               resultChannel = nil
               return
           }
           do {
               try data.write(to: url)
               filenames.append(url.path)
           } catch {
               resultChannel?(FlutterError(code: "SCAN_SAVE_ERROR", message: "failed to write a scanned page", details: nil))
               resultChannel = nil
               return
           }
       }
       resultChannel?(filenames)
       resultChannel = nil
   }

   private func saveScannedPdf(scan: VNDocumentCameraScan) {
       let tempDirPath = getDocumentsDirectory()
       let currentDateTime = Date()
       let df = DateFormatter()
       df.dateFormat = "yyyyMMdd-HHmmss"
       let formattedDate = df.string(from: currentDateTime)
       let pdfFilePath = tempDirPath.appendingPathComponent("\(formattedDate).pdf")

       let pdfDocument = PDFDocument()
       for i in 0 ..< scan.pageCount {
           let pageImage = scan.imageOfPage(at: i)
           if let pdfPage = PDFPage(image: pageImage) {
               pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
           }
       }

       do {
           try pdfDocument.write(to: pdfFilePath)
           resultChannel?(pdfFilePath.path)
           resultChannel = nil
       } catch {
           resultChannel?(FlutterError(code: "PDF_CREATION_ERROR", message: "Failed to create PDF", details: nil))
           resultChannel = nil
       }
   }

   public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
       resultChannel?(nil)
       resultChannel = nil
       presentingController?.dismiss(animated: true)
   }

   public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
       resultChannel?(FlutterError(code: "SCAN_ERROR", message: "Failed to scan documents", details: nil))
       resultChannel = nil
       presentingController?.dismiss(animated: true)
   }
}


// import Flutter
// import UIKit
// import Vision
// import VisionKit
//
// @available(iOS 13.0, *)
// public class SwiftFlutterDocScannerPlugin: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
//    var resultChannel :FlutterResult?
//    var presentingController: VNDocumentCameraViewController?
//
//   public static func register(with registrar: FlutterPluginRegistrar) {
//     let channel = FlutterMethodChannel(name: "flutter_doc_scanner", binaryMessenger: registrar.messenger())
//     let instance = SwiftFlutterDocScannerPlugin()
//     registrar.addMethodCallDelegate(instance, channel: channel)
//   }
//
//   public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
//     if call.method == "getScanDocuments" {
//             let presentedVC: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
//             self.resultChannel = result
//             self.presentingController = VNDocumentCameraViewController()
//             self.presentingController!.delegate = self
//             presentedVC?.present(self.presentingController!, animated: true)
//            } else {
//             result(FlutterMethodNotImplemented)
//             return
//        }
//   }
//
//
//     func getDocumentsDirectory() -> URL {
//         let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
//         let documentsDirectory = paths[0]
//         return documentsDirectory
//     }
//
//     public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
//         let tempDirPath = self.getDocumentsDirectory()
//         let currentDateTime = Date()
//         let df = DateFormatter()
//         df.dateFormat = "yyyyMMdd-HHmmss"
//         let formattedDate = df.string(from: currentDateTime)
//         var filenames: [String] = []
//         for i in 0 ... scan.pageCount - 1 {
//             let page = scan.imageOfPage(at: i)
//             let url = tempDirPath.appendingPathComponent(formattedDate + "-\(i).png")
//             try? page.pngData()?.write(to: url)
//             filenames.append(url.path)
//         }
//         resultChannel?(filenames)
//         presentingController?.dismiss(animated: true)
//     }
//
//     public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
//         resultChannel?(nil)
//         presentingController?.dismiss(animated: true)
//     }
//
//     public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
//         resultChannel?(nil)
//         presentingController?.dismiss(animated: true)
//     }
// }
