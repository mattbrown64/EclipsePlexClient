#if os(macOS)
import VLCKit
#elseif os(tvOS)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
extension VLCMedia {

    var duration: Duration {
        Duration.milliseconds(length.intValue)
    }
}
