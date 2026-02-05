import Foundation

extension Data {
    func readUInt16LE(at index: Int) -> UInt16? {
        guard index >= 0, count >= index + 2 else { return nil }
        let low = UInt16(self[index])
        let high = UInt16(self[index + 1]) << 8
        return low | high
    }

    func hexString(separator: String = " ") -> String {
        map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}
