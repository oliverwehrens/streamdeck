import IOKit
import Testing
@testable import DeckHID

@Test func namesElgatoAppWhenRunning() {
    let message = OpenFailure.message(code: kIOReturnExclusiveAccess, elgatoRunning: true)
    #expect(message.contains("Quit the Elgato app"))
}

@Test func explainsExclusiveAccessWithoutElgato() {
    let message = OpenFailure.message(code: kIOReturnExclusiveAccess, elgatoRunning: false)
    #expect(message.contains("exclusive access"))
    #expect(!message.contains("Elgato"))
}

@Test func showsRawCodeForUnknownErrors() {
    #expect(OpenFailure.message(code: kIOReturnNoDevice, elgatoRunning: false).contains("0xe00002c0"))
}

@Test func matchesOnlyOriginalV2() {
    #expect(IOKitTransport.vendorID == 0x0fd9)
    #expect(IOKitTransport.productID == 0x006d)
}
