import Testing
@testable import MonsterCore

@Suite("Which iPhones get the AI observer (D-028)")
struct DeviceMemoryTests {
    @Test("6 GB and bigger iPhones can run the model", arguments: [
        UInt64(5_700_000_000), 6_000_000_000, 7_600_000_000, 8_000_000_000, 12_000_000_000,
    ])
    func supported(bytes: UInt64) {
        #expect(DeviceMemory.supportsModel(physicalBytes: bytes))
    }

    @Test("3 and 4 GB iPhones play Classic Mode only", arguments: [
        UInt64(2_900_000_000), 3_000_000_000, 3_800_000_000, 4_000_000_000, 4_294_967_296,
    ])
    func unsupported(bytes: UInt64) {
        #expect(!DeviceMemory.supportsModel(physicalBytes: bytes))
    }

    @Test("Loading needs at least 1.2 GB of headroom")
    func headroom() {
        #expect(DeviceMemory.canLoadNow(availableBytes: 2_500_000_000))
        #expect(DeviceMemory.canLoadNow(availableBytes: 1_200_000_000))
        #expect(!DeviceMemory.canLoadNow(availableBytes: 1_199_999_999))
        #expect(!DeviceMemory.canLoadNow(availableBytes: 600_000_000))
        #expect(DeviceMemory.canLoadNow(availableBytes: 0), "0 means unknown, e.g. not on a device")
    }
}
