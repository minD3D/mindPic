import CoreImage
import Foundation
import Photos
import UIKit
import Vision

// MARK: - 사진 한 장 분석 (기기 안에서 Vision / Core Image로 처리)
// 비슷한 사진 묶기와 정리 추천이 함께 쓴다. 모두 작은 이미지로 분석해 빠르게 끝낸다.
enum PhotoImageAnalysis {
    // 분석용 이미지 크기. 원본 대신 작은 이미지로 분석해야 빠르다.
    static let analysisSide: CGFloat = 360

    // 기기에 있는 작은 이미지만 쓴다 (iCloud에서 받지 않음).
    static func thumbnail(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let opt = PHImageRequestOptions()
            opt.isNetworkAccessAllowed = false
            opt.deliveryMode = .highQualityFormat // 결과 핸들러가 한 번만 불린다
            opt.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: analysisSide, height: analysisSide),
                contentMode: .aspectFit,
                options: opt
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    struct Aesthetics {
        let overall: Double     // -1 ~ 1. 높을수록 잘 나온 사진
        let isUtility: Bool     // 영수증, 문서, 메모처럼 기록용으로 찍은 사진
    }

    @available(iOS 18.0, *)
    static func aesthetics(_ image: CGImage) -> Aesthetics? {
        let request = VNCalculateImageAestheticsScoresRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first as? VNImageAestheticsScoresObservation else { return nil }
        return Aesthetics(overall: Double(observation.overallScore), isUtility: observation.isUtility)
    }

    // 사진 속 얼굴들의 평균 품질 (표정, 초점, 가림). 얼굴이 없으면 nil.
    static func faceQuality(_ image: CGImage) -> Double? {
        let request = VNDetectFaceCaptureQualityRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let qualities = (request.results ?? []).compactMap { ($0 as? VNFaceObservation)?.faceCaptureQuality }
        guard !qualities.isEmpty else { return nil }
        return Double(qualities.reduce(0, +) / Float(qualities.count))
    }

    // 사진에 붙은 분류 라벨 (Vision 기본 분류 모델, 1,000개 이상). 신뢰도가 기준 이상인 것만.
    static func classificationLabels(_ image: CGImage, minimumConfidence: Float) -> Set<String> {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let observations = (request.results ?? []).compactMap { $0 as? VNClassificationObservation }
        return Set(observations.filter { $0.confidence >= minimumConfidence }.map(\.identifier))
    }

    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    // 윤곽선 세기의 평균 (0~1). 흔들리거나 초점이 나간 사진일수록 낮다.
    static func sharpness(_ image: CGImage) -> Double {
        let input = CIImage(cgImage: image)
        guard let edges = CIFilter(name: "CIEdges",
                                   parameters: [kCIInputImageKey: input, kCIInputIntensityKey: 1.0])?.outputImage,
              let rgb = averageColor(of: edges, extent: input.extent)
        else { return 0 }
        return (rgb.r + rgb.g + rgb.b) / 3
    }

    // 평균 밝기 (0~1)
    static func brightness(_ image: CGImage) -> Double {
        let input = CIImage(cgImage: image)
        guard let rgb = averageColor(of: input, extent: input.extent) else { return 0.5 }
        return 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
    }

    private static func averageColor(of image: CIImage, extent: CGRect) -> (r: Double, g: Double, b: Double)? {
        guard let average = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: image,
                                                  kCIInputExtentKey: CIVector(cgRect: extent)])?.outputImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(average, toBitmap: &pixel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}
