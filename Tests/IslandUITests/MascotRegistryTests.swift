import Testing
import SwiftUI
@testable import IslandUI

@Test func registryHasAtLeastTwelveUniqueIDs() {
    let ids = MascotRegistry.all.map(\.id)
    #expect(ids.count >= 12)
    #expect(Set(ids).count == ids.count)
}

@Test func everyMascotHasANameAndAnId() {
    for mascot in MascotRegistry.all {
        #expect(!mascot.id.isEmpty)
        #expect(!mascot.name.isEmpty)
    }
}

@Test func ghostIsTheDefaultAndUnknownIdsFallBackToIt() {
    #expect(MascotRegistry.all.first?.id == "ghost")
    #expect(MascotRegistry.definition(id: "ghost").id == "ghost")
    #expect(MascotRegistry.definition(id: "nope").id == "ghost")
}

@Test @MainActor func everyMascotRendersEveryMood() {
    for mascot in MascotRegistry.all {
        for mood in MascotMood.allCases {
            let renderer = ImageRenderer(content: BlobMascotView(mascot, mood: mood))
            renderer.scale = 2
            #expect(renderer.cgImage != nil, "\(mascot.id) / \(mood)")
        }
    }
}

@Test @MainActor func mascotsLookDifferentFromEachOther() {
    func pixels(_ id: String) -> Data? {
        let renderer = ImageRenderer(content: BlobMascotView(MascotRegistry.definition(id: id), mood: .focus))
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
        return data as Data
    }
    #expect(pixels("ghost") != nil)
    #expect(pixels("ghost") != pixels("cat"))
    #expect(pixels("cloud") != pixels("flame"))
}

@Test @MainActor func moodsLookDifferentOnTheSameMascot() {
    func pixels(_ mood: MascotMood) -> Data? {
        let renderer = ImageRenderer(content: BlobMascotView(MascotRegistry.definition(id: "ghost"), mood: mood))
        renderer.scale = 2
        return (renderer.cgImage?.dataProvider?.data) as Data?
    }
    #expect(pixels(.focus) != pixels(.rest))
    #expect(pixels(.rest) != pixels(.done))
    #expect(pixels(.focus) != pixels(.done))
}
