import Foundation
var checks = 0
func check(_ name: String, _ ok: Bool) {
    checks += 1
    if !ok { print("FAIL \(name)"); exit(1) }
}
func reply(_ p: [UInt8]) -> [UInt8] { [0x11, 0xFF, 3, 0x1C] + p }
let caps = reply([1]), current = reply([2, 37, 81])
check("torque preserves MX4 mode and threshold", SolaarFeatures.torque(caps, current, 23) == [2,37,23])
for value in -1...102 { check("torque bounds", (SolaarFeatures.torque(caps,current,value) != nil) == (1...100).contains(value)) }
check("no capability", SolaarFeatures.torque(reply([0]),current,1) == nil)
check("short/invalid mode", SolaarFeatures.torque(caps,reply([0,3,4]),1) == nil && SolaarFeatures.torque(caps,[],1) == nil)
check("torque readback requires preserved fields", !SolaarFeatures.matches(reply([1,37,23]),[2,37,23]))
check("missing readback", !SolaarFeatures.matches(nil,[1]) && !SolaarFeatures.matches([],[]) && !SolaarFeatures.matches(reply([]),[1]))
for original in 0...255 {
    for on in [true,false] {
        let r = reply([0xAB,UInt8(original)])
        let p = SolaarFeatures.masked(r, byte: 1, mask: 1, on: on, width: 2)!
        check("thumb masks second byte only", p == [0xAB, on ? UInt8(original) | 1 : UInt8(original) & 0xFE])
        check("thumb parsed", SolaarFeatures.maskValue(reply(p),byte:1,mask:1,width:2) == on)
        check("thumb confirmed", SolaarFeatures.matches(reply(p),p))
        let h = SolaarFeatures.masked(reply([UInt8(original)]),byte:0,mask:2,on:on,width:1)!
        check("hires preserves invert/target/unknown bits", h[0] & 0xFD == UInt8(original) & 0xFD)
        check("hires parsed", SolaarFeatures.maskValue(reply(h),byte:0,mask:2,width:1) == on)
        check("readback rejects unrelated bit loss", !SolaarFeatures.matches(reply([h[0] ^ 0x80]),h))
    }
}
check("invalid mask inputs", SolaarFeatures.masked([],byte:0,mask:1,on:true,width:2) == nil && SolaarFeatures.maskValue(nil,byte:0,mask:1,width:1) == nil)
for bit in 0..<8 {
    let c = reply([UInt8(1 << bit)]), old = reply([0xA5])
    let p = SolaarFeatures.disabledKey(c,old,bit:bit,disabled:true)
    check("disable advertised bits only", p == [0xA5 | UInt8(1 << bit)])
    check("disable preserves all other bits", SolaarFeatures.disabledKey(c,old,bit:bit,disabled:false) == [0xA5 & ~UInt8(1 << bit)])
    check("unadvertised key rejected", SolaarFeatures.disabledKey(reply([0]),old,bit:bit,disabled:true) == nil)
}
check("disable out of range", SolaarFeatures.disabledKey(caps,current,bit:8,disabled:true) == nil)
check("names", SolaarFeatures.disableName(0) == "Caps Lock" && SolaarFeatures.disableName(4) == "Win / ⌘")
let platform = SolaarFeatures.platform(reply([7,0,0x20,0,10,0,15,2]))!
check("descriptor id and BE OS/version", platform.id == 7 && platform.name == "macOS 10–15.2")
let choices = [platform]
let info = reply([2,0,1,0,0,0,7])
check("current channel platform prefix", SolaarFeatures.platformWrite(info,choices:choices,selected:7) == [0xFF,7])
check("unknown platform rejected", SolaarFeatures.platformWrite(info,choices:choices,selected:0) == nil)
check("read-only rejected", SolaarFeatures.platformWrite(reply([0,0,1,0,0,0,7]),choices:choices,selected:7) == nil)
check("platform readback", SolaarFeatures.platformMatches(info,selected:7,beforeHost:1,afterHost:1))
check("platform mismatch/channel change rejected", !SolaarFeatures.platformMatches(info,selected:8,beforeHost:1,afterHost:1) && !SolaarFeatures.platformMatches(info,selected:7,beforeHost:1,afterHost:2))
check("bad/unknown descriptor", SolaarFeatures.platform([]) == nil && SolaarFeatures.platform(reply([7,0,0,0,0,0,0,0])) == nil)
for mode: UInt8 in [0,1,2,3] {
    let light = reply([1,(mode << 3) | 5,0x38,0x34,0x12,6,0x34,0x12,0x78,0x56,0xBC,0x9A])
    check("delay LE seconds", SolaarFeatures.duration(light,field:0) == 0x1234 * 5 && SolaarFeatures.duration(light,field:2) == 0x9ABC * 5)
    for field in 0..<3 {
        for seconds in 1...600 {
            let p = SolaarFeatures.backlightDelay(light,version:3,field:field,seconds:seconds)!
            let i = 4 + field*2
            check("delay ceiling units", Int(p[i]) | Int(p[i+1]) << 8 == (seconds+4)/5)
            check("backlight prefix keeps mode/options/power", Array(p[0...3]) == [1,(mode << 3) | 5,0xFF,mode == 3 ? 6 : 0])
            var after = light
            for f in 0..<3 {
                if f != field { check("unselected durations preserved", p[4+f*2] == light[10+f*2] && p[5+f*2] == light[11+f*2]) }
                after[10+f*2] = p[4+f*2]; after[11+f*2] = p[5+f*2]
            }
            check("delay verified", SolaarFeatures.backlightMatches(after,p))
            after[10+field*2] ^= 1
            check("delay mismatch rejected", !SolaarFeatures.backlightMatches(after,p))
        }
    }
    check("version and bounds", SolaarFeatures.backlightDelay(light,version:2,field:0,seconds:30) == nil && SolaarFeatures.backlightDelay(light,version:3,field:0,seconds:0) == nil && SolaarFeatures.backlightDelay(light,version:3,field:0,seconds:601) == nil)
}
check("malformed backlight", SolaarFeatures.duration([],field:0) == nil && !SolaarFeatures.backlightMatches([],[]) && SolaarFeatures.backlightDelay([],version:3,field:0,seconds:30) == nil)
var off = reply([0,0x0D,0x38,0,0,0,6,0,12,0,24,0])
let offPacket = SolaarFeatures.backlightDelay(off,version:3,field:0,seconds:1)!
check("delay never enables a disabled backlight", offPacket[0] == 0 && offPacket[1] == 0x0D && offPacket[2] == 0xFF && offPacket[3] == 0)
off[10] = 1
check("disabled backlight verified", SolaarFeatures.backlightMatches(off,offPacket))
off[4] = 1
check("power change rejected", !SolaarFeatures.backlightMatches(off,offPacket))
check("invalid delay field", SolaarFeatures.backlightDelay(off,version:3,field:3,seconds:1) == nil)
let multi = SolaarFeatures.platforms([reply([4,0,0x05,0,0,0,0,0]), reply([9,0,0x05,0,0,0,0,0])])
check("OS priorities and duplicate labels match Solaar", multi == [.init(id:4,name:"Linux"), .init(id:9,name:"Windows")])
let old = try JSONDecoder().decode(DeviceSettings.self, from: Data(#"{"dpi":1000,"wheelInvert":true}"#.utf8))
check("old config leaves features unset", old.ratchetTorque == nil && old.thumbInvert == nil && old.hiresResolution == nil && old.dpi == 1000)
var saved = old
saved.ratchetTorque = 78; saved.thumbInvert = true; saved.hiresResolution = false
check("new config roundtrip", try JSONDecoder().decode(DeviceSettings.self,from: JSONEncoder().encode(saved)) == saved)
check("new fields optional", try JSONDecoder().decode(DeviceSettings.self,from: Data("{}".utf8)).wheelInvert == nil)
print("PASS \(checks) protocol / persistence assertions (features 1–6)")
