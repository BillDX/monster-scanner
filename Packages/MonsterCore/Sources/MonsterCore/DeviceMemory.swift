/// Which iPhones get the AI observer (DECISIONS.md D-028).
///
/// The model peaks just under 1 GB (953–978 MB measured on an iPhone 14 Pro).
/// iOS 17 also runs on 3 and 4 GB iPhones (XR, XS, 11, 12, 13, SE), where that
/// would risk the app being killed mid-scan, so those play Classic Mode only.
public enum DeviceMemory {
    /// 6 GB iPhones report a little under 6 GB; 4 GB ones a little under 4 GB.
    /// 5 GB splits them cleanly.
    public static let minimumPhysicalBytes: UInt64 = 5_000_000_000

    /// Before loading, iOS must allow the app at least this much more memory:
    /// the model's peak plus room for the camera and the reveal.
    public static let minimumAvailableBytes: UInt64 = 1_200_000_000

    /// Whether this iPhone can ever run the model (decides whether the
    /// 1.55 GB download is offered at all).
    public static func supportsModel(physicalBytes: UInt64) -> Bool {
        physicalBytes >= minimumPhysicalBytes
    }

    /// Whether it is safe to load the model right now. `availableBytes` of 0
    /// means "unknown" (not on a device) and is allowed.
    public static func canLoadNow(availableBytes: UInt64) -> Bool {
        availableBytes == 0 || availableBytes >= minimumAvailableBytes
    }
}
