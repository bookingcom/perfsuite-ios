import Foundation
import XCTest
@testable import PerformanceSuite

final class CrashlyticsIssueReporterTests: XCTestCase {
    func testStackTraceParsing() {
        let reporter = CrashlyticsIssueReporter(fatalHangsAsCrashes: true, firebaseHangReason: "reason")
        let stack = """
            0   libsystem_kernel.dylib         0x00000002036a2c88 0x00000002036a1000 + 8
            1   libsystem_pthread.dylib        0x0000000224325114 0x0000000224323000 + 84
            2   libsystem_pthread.dylib        0x000000022432c318 0x0000000224323000 + 248
            3   SwiftUI                        0x00000001c822c7e4 0x00000001c821a000 + 48
            4   SwiftUI                        0x00000001c82a2a00 0x00000001c821a000 + 11396
            5   SwiftUI                        0x00000001c822aec0 0x00000001c821a000 + 72
            6   UIKitAdditions                      0x00000001c6a84898 0x00000001c69f7000 + 224
            7   UIKitAdditions                      0x00000001c6c11508 0x00000001c69f7000 + 112
            8   UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            9   UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            10  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            11  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            12  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            13  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            14  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            15  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            16  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            17  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            18  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            19  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            20  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            21  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            22  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            23  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            24  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            25  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            26  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            27  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            28  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            29  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            30  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            31  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            32  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            33  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            34  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            35  UIKitAdditions                      0x00000001c6c11564 0x00000001c69f7000 + 68
            36  UIKitAdditions                      0x00000001c6c114d8 0x00000001c69f7000 + 64
            37  UIKitAdditions                      0x00000001c6c138dc 0x00000001c69f7000 + 56
            38  UIKitAdditions                      0x00000001c6c11344 0x00000001c69f7000 + 516
            39  UIKitAdditions                      0x00000001c6c11130 0x00000001c69f7000 + 120
            40  UIKitAdditions                      0x00000001c6ac6e54 0x00000001c69f7000 + 152
            41  Booking.com                    0x00000001036e0d4c 0x00000001007ac000 + 49499468
            42  Booking.com                    0x00000001037b7518 0x00000001007ac000 + 50378008
            43  Booking.com                    0x0000000100fbe7c0 0x00000001007ac000 + 8464320
            44  libdispatch.dylib              0x00000001cbe51eac 0x00000001cbe4e000 + 20
            45  libdispatch.dylib              0x00000001cbe55330 0x00000001cbe4e000 + 504
            46  libdispatch.dylib              0x00000001cbe68908 0x00000001cbe4e000 + 1588
            47  libdispatch.dylib              0x00000001cbe605f8 0x00000001cbe4e000 + 756
            48  libdispatch.dylib              0x00000001cbe602f4 0x00000001cbe4e000 + 44
            49  CoreFoundation                 0x00000001c4a21d18 0x00000001c4989000 + 16
            50  CoreFoundation                 0x00000001c4a03650 0x00000001c4989000 + 1992
            51  CoreFoundation                 0x00000001c4a084dc 0x00000001c4989000 + 612
            52  GraphicsServices               0x00000001ffc7435c 0x00000001ffc73000 + 164
            53  UIKitAdditions                      0x00000001c6d9437c 0x00000001c69f7000 + 888
            54  UIKitAdditions                      0x00000001c6d93fe0 0x00000001c69f7000 + 340
            55  Booking.com                    0x0000000100f49738 0x00000001007ac000 + 7984952
            56  dyld                           0x00000001e3e9cdec 0x00000001e3e87000 + 2220
            """

        let addresses: [UInt] = [
            0x0000_0002_036a_2c88,
            0x0000_0002_2432_5114,
            0x0000_0002_2432_c318,
            0x0000_0001_c822_c7e4,
            0x0000_0001_c82a_2a00,
            0x0000_0001_c822_aec0,
            0x0000_0001_c6a8_4898,
            0x0000_0001_c6c1_1508,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_1564,
            0x0000_0001_c6c1_14d8,
            0x0000_0001_c6c1_38dc,
            0x0000_0001_c6c1_1344,
            0x0000_0001_c6c1_1130,
            0x0000_0001_c6ac_6e54,
            0x0000_0001_036e_0d4c,
            0x0000_0001_037b_7518,
            0x0000_0001_00fb_e7c0,
            0x0000_0001_cbe5_1eac,
            0x0000_0001_cbe5_5330,
            0x0000_0001_cbe6_8908,
            0x0000_0001_cbe6_05f8,
            0x0000_0001_cbe6_02f4,
            0x0000_0001_c4a2_1d18,
            0x0000_0001_c4a0_3650,
            0x0000_0001_c4a0_84dc,
            0x0000_0001_ffc7_435c,
            0x0000_0001_c6d9_437c,
            0x0000_0001_c6d9_3fe0,
            0x0000_0001_00f4_9738,
            0x0000_0001_e3e9_cdec,
        ]

        let expectedFrames = addresses.map { StackFrame(address: $0) }
        let frames = reporter.parse(stackTrace: stack)

        for i in 0..<frames.count {
            XCTAssertEqual(frames[i].description, expectedFrames[i].description)
        }
    }
}
