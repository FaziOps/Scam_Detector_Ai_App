import Foundation
import Vision
import AppKit

func performOCR(imagePath: String) {
    let url = URL(fileURLWithPath: imagePath)
    guard let image = NSImage(contentsOf: url),
          let tiffData = image.tiffRepresentation,
          let imageSource = CGImageSourceCreateWithData(tiffData as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("Error: Could not load image from \(imagePath)")
        exit(1)
    }
    
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest { (request, error) in
        if let error = error {
            print("Error recognizing text: \(error)")
            exit(1)
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return
        }
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        print(recognizedStrings.joined(separator: "\n"))
    }
    
    request.recognitionLevel = .accurate
    
    do {
        try requestHandler.perform([request])
    } catch {
        print("Error performing Vision request: \(error)")
        exit(1)
    }
}

let args = CommandLine.arguments
if args.count < 2 {
    print("Usage: ocr <image_path>")
    exit(1)
}
performOCR(imagePath: args[1])
