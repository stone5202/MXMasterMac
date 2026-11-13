import Foundation

// HID++ payload codecs, independently implemented from Solaar's protocol descriptions.
// Inputs are complete HID++ replies (four-byte header); outputs are function parameters.
// settings_templates.py: ScrollRatchetTorque, DisableKeyboardKeys, Multiplatform,
// Backlight2Duration*, ThumbInvert, HiresSmoothResolution; hidpp20.py: Backlight.
enum SolaarFeatures {
    static func torque(_ caps: [UInt8]?, _ current: [UInt8]?, _ value: Int) -> [UInt8]? {
        guard let caps, caps.count >= 5, caps[4] & 1 != 0,
              let current, current.count >= 7, (1...2).contains(current[4]),
              (1...100).contains(value) else { return nil }
        return [current[4], current[5], UInt8(value)]
    }

    static func maskValue(_ reply: [UInt8]?, byte: Int, mask: UInt8, width: Int) -> Bool? {
        guard let reply, byte >= 0, byte < width, reply.count >= 4 + width else { return nil }
        return reply[4 + byte] & mask != 0
    }

    static func matches(_ reply: [UInt8]?, _ parameters: [UInt8]?) -> Bool {
        guard let reply, let parameters, !parameters.isEmpty, reply.count >= 4 + parameters.count else { return false }
        return Array(reply[4..<4 + parameters.count]) == parameters
    }

    static func masked(_ current: [UInt8]?, byte: Int, mask: UInt8, on: Bool, width: Int) -> [UInt8]? {
        guard let current, width > 0, byte >= 0, byte < width, current.count >= 4 + width else { return nil }
        var payload = Array(current[4..<4 + width])
        payload[byte] = on ? payload[byte] | mask : payload[byte] & ~mask
        return payload
    }

    static func disabledKey(_ caps: [UInt8]?, _ current: [UInt8]?, bit: Int, disabled: Bool) -> [UInt8]? {
        guard let caps, caps.count >= 5, (0..<8).contains(bit), caps[4] & (1 << bit) != 0 else { return nil }
        return masked(current, byte: 0, mask: 1 << bit, on: disabled, width: 1)
    }

    // special_keys.py DISABLE. Future device-advertised bits remain individually selectable.
    static func disableName(_ bit: Int) -> String {
        let names = ["Caps Lock", "Num Lock", "Scroll Lock", "Insert", "Win / ⌘"]
        return names.indices.contains(bit) ? names[bit] : String(format: "0x%02X", 1 << bit)
    }

    struct Platform: Equatable, Identifiable {
        var id: Int
        var name: String
    }

    static func platform(_ descriptor: [UInt8]?, os: Int = 0) -> Platform? {
        guard let d = descriptor, d.count >= 12 else { return nil }
        let flags = Int(d[6]) << 8 | Int(d[7])
        let names: [(String, Int)] = [("Linux", 0x0400), ("macOS", 0x2000), ("Windows", 0x0100),
                                     ("iOS", 0x4000), ("Android", 0x1000), ("WebOS", 0x8000),
                                     ("Chrome", 0x0800), ("WinEmb", 0x0200), ("Tizen", 0x0001)]
        guard let name = names.first(where: { flags & $0.1 != 0 && (os == 0 || os == $0.1) })?.0 else { return nil }
        let low = Int(d[8]) << 8 | Int(d[9]), high = Int(d[10]) << 8 | Int(d[11])
        func version(_ v: Int) -> String { v == 0 ? "" : v & 255 == 0 ? "\(v >> 8)" : "\(v >> 8).\(v & 255)" }
        return Platform(id: Int(d[4]), name: name + (low == 0 && high == 0 ? "" : " \(version(low))–\(version(high))"))
    }

    static func platforms(_ descriptors: [[UInt8]]) -> [Platform] {
        var choices: [Platform] = []
        for os in [0x0400, 0x2000, 0x0100, 0x4000, 0x1000, 0x8000, 0x0800, 0x0200, 0x0001] {
            for descriptor in descriptors {
                if let p = platform(descriptor, os: os), !choices.contains(where: { $0.id == p.id || $0.name == p.name }) {
                    choices.append(p)
                }
            }
        }
        return choices
    }

    static func platformWrite(_ info: [UInt8]?, choices: [Platform], selected: Int) -> [UInt8]? {
        guard let info, info.count >= 11, info[4] & 2 != 0,
              (0...255).contains(selected), choices.contains(where: { $0.id == selected }) else { return nil }
        return [0xFF, UInt8(selected)]       // current Easy-Switch channel
    }

    static func platformMatches(_ info: [UInt8]?, selected: Int, beforeHost: Int, afterHost: Int) -> Bool {
        guard let info, info.count >= 11, beforeHost >= 0, beforeHost == afterHost else { return false }
        return Int(info[10]) == selected
    }

    static func duration(_ reply: [UInt8]?, field: Int) -> Int? {
        guard let reply, reply.count >= 16, (0..<3).contains(field) else { return nil }
        let i = 10 + field * 2
        return (Int(reply[i]) | Int(reply[i + 1]) << 8) * 5
    }

    static func backlightDelay(_ reply: [UInt8]?, version: Int, field: Int, seconds: Int) -> [UInt8]? {
        guard let r = reply, r.count >= 16, version >= 3, (0..<3).contains(field), (1...600).contains(seconds) else { return nil }
        let mode = (r[5] >> 3) & 3
        var payload: [UInt8] = [r[4], (r[5] & 7) | (mode << 3), 0xFF, mode == 3 ? r[9] : 0]
        payload += Array(r[10...15])
        let units = (seconds + 4) / 5, i = 4 + field * 2
        payload[i] = UInt8(units & 255)
        payload[i + 1] = UInt8(units >> 8)
        return payload
    }

    static func backlightMatches(_ reply: [UInt8]?, _ packet: [UInt8]?) -> Bool {
        guard let r = reply, r.count >= 16, let p = packet, p.count == 10 else { return false }
        return r[4] == p[0] && r[5] & 0x1F == p[1] &&
            ((p[1] >> 3) & 3 != 3 || r[9] == p[3]) && Array(r[10...15]) == Array(p[4...9])
    }
}
