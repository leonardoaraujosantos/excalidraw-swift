import ExcalidrawModel
import Foundation

/// Embeds a `.excalidraw` scene inside an exported PNG (and reads it back) so an
/// exported image can be re-opened as an editable drawing — the PNG scene-embed
/// round-trip. The scene JSON is base64-encoded into a PNG `tEXt` chunk keyed
/// `excalidraw`, inserted right after `IHDR`. Base64 keeps the payload ASCII
/// (PNG `tEXt` is Latin-1), so UTF-8 scenes survive intact.
public enum PNGSceneEmbed {
    static let keyword = "excalidraw"
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Insert `scene` into `pngData`, returning new PNG bytes (or `nil` if the
    /// input isn't a PNG or the scene can't be encoded).
    public static func embed(_ scene: Scene, into pngData: Data) -> Data? {
        guard hasSignature(pngData), pngData.count >= 8 + 25,
              let json = try? SceneDocument.encode(scene, prettyPrinted: false) else { return nil }
        let text = Array(keyword.utf8) + [0] + Array(json.base64EncodedString().utf8)
        let chunk = makeChunk(type: "tEXt", data: text)

        // IHDR is always the first chunk: signature(8) + len(4)+type(4)+data(13)+crc(4) = 33.
        let insertAt = 8 + 25
        var out = Data()
        out.append(pngData.prefix(insertAt))
        out.append(contentsOf: chunk)
        out.append(pngData.suffix(from: pngData.startIndex + insertAt))
        return out
    }

    /// Extract an embedded scene from `pngData`, or `nil` when there's none.
    public static func extractScene(from pngData: Data) -> Scene? {
        guard let base64 = extractText(from: pngData),
              let json = Data(base64Encoded: base64) else { return nil }
        return try? SceneDocument.decode(json)
    }

    /// Whether `pngData` carries an embedded scene.
    public static func containsScene(_ pngData: Data) -> Bool {
        extractText(from: pngData) != nil
    }

    // MARK: - Chunk walking

    private static func extractText(from pngData: Data) -> String? {
        guard hasSignature(pngData) else { return nil }
        let bytes = [UInt8](pngData)
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = Int(bigEndian: bytes, at: offset)
            let typeStart = offset + 4
            guard typeStart + 4 <= bytes.count else { return nil }
            let type = String(bytes: bytes[typeStart ..< typeStart + 4], encoding: .ascii)
            let dataStart = typeStart + 4
            guard dataStart + length + 4 <= bytes.count else { return nil }
            if type == "tEXt" {
                let chunk = Array(bytes[dataStart ..< dataStart + length])
                if let nul = chunk.firstIndex(of: 0),
                   String(bytes: chunk[0 ..< nul], encoding: .ascii) == keyword {
                    return String(bytes: chunk[(nul + 1)...], encoding: .ascii)
                }
            }
            if type == "IEND" { return nil }
            offset = dataStart + length + 4 // skip data + CRC
        }
        return nil
    }

    private static func makeChunk(type: String, data: [UInt8]) -> [UInt8] {
        let typeBytes = Array(type.utf8)
        var chunk = lengthBytes(data.count)
        chunk += typeBytes
        chunk += data
        chunk += crc32Bytes(typeBytes + data)
        return chunk
    }

    private static func hasSignature(_ data: Data) -> Bool {
        data.count >= 8 && Array(data.prefix(8)) == signature
    }

    private static func lengthBytes(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private static func crc32Bytes(_ bytes: [UInt8]) -> [UInt8] {
        let crc = CRC32.checksum(bytes)
        return lengthBytes(Int(crc))
    }
}

private extension Int {
    /// Read a big-endian UInt32 length from `bytes` at `offset`.
    init(bigEndian bytes: [UInt8], at offset: Int) {
        self = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
            | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
    }
}

/// Standard PNG/zlib CRC-32 (polynomial 0xEDB88320).
enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0 ..< 8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
