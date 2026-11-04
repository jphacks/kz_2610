import XCTest
import SwiftUI
import CoreImage.CIFilterBuiltins
import Vision
@testable import meshinowa

final class InviteLinkTests: XCTestCase {
    @MainActor func testVisionCompatibilityWhenCPUDecoderIsAvailable() throws {
        let raw = "https://invite.example.test/i/" + String(repeating: "a", count: 64)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(raw.utf8); filter.correctionLevel = "H"
        let ci = try XCTUnwrap(filter.outputImage).transformed(by: .init(scaleX: 8, y: 8))
        func decode(_ cg: CGImage) throws -> String? {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            request.usesCPUOnly = true
            try VNImageRequestHandler(cgImage: cg).perform([request])
            return request.results?.first?.payloadStringValue
        }
        let standard = try XCTUnwrap(CIContext().createCGImage(ci, from: ci.extent))
        guard try decode(standard) == raw else {
            throw XCTSkip("この環境ではVisionのCPU処理が標準QRも読み取れないため、Core Imageの読み取りで検証する。")
        }
        let renderer = ImageRenderer(content: InviteQRCodeView(code: try XCTUnwrap(InviteQRCode(url: URL(string: raw)!))))
        renderer.scale = 3
        XCTAssertEqual(try decode(XCTUnwrap(renderer.uiImage?.cgImage)), raw)
    }

    @MainActor func testQRMatrixOrientationAndBaseline() throws {
        let raw = "https://invite.example.test/i/" + String(repeating: "a", count: 64)
        let code = try XCTUnwrap(InviteQRCode(url: URL(string: raw)!))
        let n = code.modules.count
        for (x, y) in [(0, 0), (n - 7, 0), (0, n - 7)] {
            XCTAssertTrue((0..<7).allSatisfy { code.modules[y][x + $0] }, "角の目の上辺")
            XCTAssertTrue((0..<7).allSatisfy { code.modules[y + $0][x] }, "角の目の左辺")
        }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(raw.utf8); filter.correctionLevel = "H"
        let ci = try XCTUnwrap(filter.outputImage).transformed(by: .init(scaleX: 8, y: 8))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        XCTAssertEqual((detector.features(in: ci).first as? CIQRCodeFeature)?.messageString, raw, "標準QR")
        let renderer = ImageRenderer(content: InviteQRCodeView(code: code))
        renderer.scale = 3
        let cg = try XCTUnwrap(renderer.uiImage?.cgImage)
        XCTAssertEqual((detector.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString, raw, "装飾QR・Core Image")
    }

    @MainActor func testStyledQRCodeDecodesAtDisplaySizes() throws {
        let token = "0123456789abcdef" + String(repeating: "a73d09c2b85f641e", count: 3)
        let urls = ["https://invite.example.test/i/\(token)",
                    "https://meshinowa-development-invites.example.test/i/\(String(token.reversed()))"]
        for raw in urls {
            let code = try XCTUnwrap(InviteQRCode(url: URL(string: raw)!))
            for size: CGFloat in [176, 184] {
                for scale: CGFloat in [1, 3] {
                    let renderer = ImageRenderer(content: InviteQRCodeView(code: code, size: size))
                    renderer.scale = scale
                    let image = try XCTUnwrap(renderer.uiImage)
                    let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                                           options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
                    let decoded = detector.features(in: CIImage(cgImage: try XCTUnwrap(image.cgImage)))
                        .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                    XCTAssertEqual(decoded.first, raw,
                                   "\(Int(size))pt・\(Int(scale))倍の装飾QRを読み取れること")
                    if size == 184 && scale == 3 {
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "招待QR・緑のつぶ・デモ用"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    func testOnlyValidTokensAndTrustedOriginsAreAccepted() throws {
        let token = String(repeating: "a", count: 64)
        let origin = URL(string: "https://invite.example.test")!
        XCTAssertEqual(InviteLink.token(from: URL(string: "meshinowa://invite/\(token)")!, backendURL: nil), token)
        XCTAssertEqual(InviteLink.token(from: origin.appendingPathComponent("i/\(token)"), backendURL: origin), token)
        for raw in ["https://evil.example.test/i/\(token)", "https://invite.example.test/i/short",
                    "https://invite.example.test/i/\(token)?redirect=evil", "meshinowa://invite/../\(token)",
                    "http://invite.example.test/i/\(token)"] {
            XCTAssertNil(InviteLink.token(from: URL(string: raw)!, backendURL: origin))
        }
    }
}
