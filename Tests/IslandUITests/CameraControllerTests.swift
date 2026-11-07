import Testing
@testable import IslandUI

private final class FakeAuthorizer: CameraAuthorizing {
    var access: CameraAccess
    var grantsWhenAsked = true
    private(set) var requests = 0
    /// Runs while the permission prompt is "open", to simulate things that happen meanwhile.
    var duringPrompt: (() -> Void)?

    init(_ access: CameraAccess) { self.access = access }

    func currentAccess() -> CameraAccess { access }

    func requestAccess() async -> Bool {
        requests += 1
        duringPrompt?()
        if grantsWhenAsked { access = .authorized } else { access = .denied }
        return grantsWhenAsked
    }
}

private final class FakeCapture: CameraCapturing {
    var hasCamera = true
    private(set) var starts = 0
    private(set) var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor
private func makeController(
    _ access: CameraAccess, hasCamera: Bool = true
) -> (CameraController, FakeAuthorizer, FakeCapture) {
    let authorizer = FakeAuthorizer(access)
    let capture = FakeCapture()
    capture.hasCamera = hasCamera
    return (CameraController(authorizer: authorizer, capture: capture), authorizer, capture)
}

@Test @MainActor func withPermissionTheCameraStartsWithoutAsking() async {
    let (controller, authorizer, capture) = makeController(.authorized)
    await controller.start()
    #expect(controller.state == .running)
    #expect(capture.starts == 1)
    #expect(authorizer.requests == 0)
}

@Test @MainActor func theFirstVisitAsksForPermissionOnceThenRuns() async {
    let (controller, authorizer, capture) = makeController(.notDetermined)
    await controller.start()
    #expect(authorizer.requests == 1)
    #expect(controller.state == .running)
    #expect(capture.starts == 1)
}

@Test @MainActor func refusingThePermissionPromptMeansDeniedAndTheCameraNeverStarts() async {
    let (controller, authorizer, capture) = makeController(.notDetermined)
    authorizer.grantsWhenAsked = false
    await controller.start()
    #expect(controller.state == .denied)
    #expect(capture.starts == 0)
}

@Test @MainActor func aDeniedCameraIsNeverAskedAgainAndNeverStarted() async {
    let (controller, authorizer, capture) = makeController(.denied)
    await controller.start()
    #expect(controller.state == .denied)
    #expect(authorizer.requests == 0)
    #expect(capture.starts == 0)
}

@Test @MainActor func aRestrictedCameraShowsTheRestrictedState() async {
    let (controller, _, capture) = makeController(.restricted)
    await controller.start()
    #expect(controller.state == .restricted)
    #expect(capture.starts == 0)
}

@Test @MainActor func aMacWithNoCameraSaysSoInsteadOfStarting() async {
    let (controller, _, capture) = makeController(.authorized, hasCamera: false)
    await controller.start()
    #expect(controller.state == .noCamera)
    #expect(capture.starts == 0)
}

@Test @MainActor func stoppingTurnsTheCameraOff() async {
    let (controller, _, capture) = makeController(.authorized)
    await controller.start()
    controller.stop()
    #expect(controller.state == .stopped)
    #expect(capture.stops == 1)
}

@Test @MainActor func stoppingWhenNeverStartedIsHarmless() {
    let (controller, _, capture) = makeController(.authorized)
    controller.stop()
    #expect(controller.state == .stopped)
    #expect(capture.starts == 0)
}

@Test @MainActor func startingTwiceDoesNotStartTheCameraTwice() async {
    let (controller, _, capture) = makeController(.authorized)
    await controller.start()
    await controller.start()
    #expect(capture.starts == 1)
}

@Test @MainActor func leavingTheTabWhileThePermissionPromptIsOpenNeverTurnsTheCameraOn() async {
    let (controller, authorizer, capture) = makeController(.notDetermined)
    authorizer.duringPrompt = { controller.stop() }
    await controller.start()
    #expect(capture.starts == 0)
    #expect(controller.state == .stopped)
}

@Test @MainActor func permissionGrantedLaterInSystemSettingsWorksOnTheNextVisit() async {
    let (controller, authorizer, capture) = makeController(.denied)
    await controller.start()
    #expect(controller.state == .denied)

    authorizer.access = .authorized
    await controller.start()
    #expect(controller.state == .running)
    #expect(capture.starts == 1)
}

@Test @MainActor func theCameraCanBeRestartedAfterStopping() async {
    let (controller, _, capture) = makeController(.authorized)
    await controller.start()
    controller.stop()
    await controller.start()
    #expect(controller.state == .running)
    #expect(capture.starts == 2)
}
