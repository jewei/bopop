import AppKit

/// Turns a user-picked image into the palette's custom icon asset: an
/// aspect-fill square crop, downscaled to a fixed size, encoded as PNG.
/// Pure function (NSImage in, Data out) — no I/O. `SettingsModel` owns the
/// file write (atomic + 0600), mirroring `Storage.save`'s conventions.
enum BrandImageImporter {
    static let targetSize = 128

    static func importedPNGData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let side = min(cgImage.width, cgImage.height)
        guard side > 0 else {
            return nil
        }
        let xOffset = (cgImage.width - side) / 2
        let yOffset = (cgImage.height - side) / 2
        guard let cropped = cgImage.cropping(
            to: CGRect(x: xOffset, y: yOffset, width: side, height: side)
        ) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        guard let scaled = context.makeImage() else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .png, properties: [:])
    }
}
