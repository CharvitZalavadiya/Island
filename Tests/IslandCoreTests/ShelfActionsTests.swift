import Testing
import Foundation
@testable import IslandCore

private func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }

@Test func nothingSelectedOffersNothing() {
    let actions = ShelfActions.make(for: [])
    #expect(!actions.canZip && !actions.canUnzip && !actions.canShowInFinder && !actions.canAirDrop && !actions.canRemove)
    #expect(actions.convertFormats.isEmpty)
}

@Test func onePNGOffersTheOtherFormatsFinderAirDropAndRemove() {
    let actions = ShelfActions.make(for: urls("photo.png"))
    #expect(actions.convertFormats == [.heic, .jpeg, .tiff, .pdf])
    #expect(actions.canShowInFinder && actions.canAirDrop && actions.canRemove)
    #expect(!actions.canZip && !actions.canUnzip)
}

@Test func twoFilesOfferZipButNotShowInFinder() {
    let actions = ShelfActions.make(for: urls("a.txt", "b.txt"))
    #expect(actions.canZip)
    #expect(!actions.canShowInFinder)
    #expect(actions.canAirDrop && actions.canRemove)
    #expect(actions.convertFormats.isEmpty)
}

@Test func twoPNGsLeaveOutPNGAndStillOfferZip() {
    let actions = ShelfActions.make(for: urls("a.png", "b.png"))
    #expect(actions.convertFormats == [.heic, .jpeg, .tiff, .pdf])
    #expect(actions.canZip)
}

@Test func aPNGAndAJPEGTogetherOfferEveryFormat() {
    // Neither format is shared by all of them, so none is left out.
    let actions = ShelfActions.make(for: urls("a.png", "b.jpg"))
    #expect(actions.convertFormats == ImageFormat.allCases)
}

@Test func aMixedSelectionOffersNoConversionButStillZips() {
    let actions = ShelfActions.make(for: urls("a.png", "notes.txt"))
    #expect(actions.convertFormats.isEmpty)
    #expect(actions.canZip)
}

@Test func aPDFOffersTheImageFormats() {
    #expect(ShelfActions.make(for: urls("doc.pdf")).convertFormats == [.heic, .png, .jpeg, .tiff])
}

@Test func extensionsAreMatchedWithoutCaseAndWithTheirAliases() {
    #expect(ShelfActions.make(for: urls("A.PNG")).convertFormats == [.heic, .jpeg, .tiff, .pdf])
    #expect(ShelfActions.make(for: urls("a.JPEG")).convertFormats == [.heic, .png, .tiff, .pdf])
    #expect(ShelfActions.make(for: urls("a.jpg")).convertFormats == [.heic, .png, .tiff, .pdf])
    #expect(ShelfActions.make(for: urls("a.tif")).convertFormats == [.heic, .png, .jpeg, .pdf])
}

@Test func anImageFormatIslandCannotWriteStillOffersEveryFormat() {
    // A GIF can be read but is none of the output formats, so nothing is left out.
    #expect(ShelfActions.make(for: urls("anim.gif")).convertFormats == ImageFormat.allCases)
}

@Test func oneZipOffersUnzipButTwoDoNot() {
    #expect(ShelfActions.make(for: urls("a.zip")).canUnzip)
    #expect(ShelfActions.make(for: urls("a.zip")).convertFormats.isEmpty)
    let two = ShelfActions.make(for: urls("a.zip", "b.zip"))
    #expect(!two.canUnzip)
    #expect(two.canZip)
}

@Test func aSingleTextFileHasNoConversion() {
    let actions = ShelfActions.make(for: urls("notes.txt"))
    #expect(actions.convertFormats.isEmpty)
    #expect(actions.canShowInFinder)
}

@Test func whichFilesCanBeConvertedOrUnzipped() {
    for name in ["a.png", "a.HEIC", "a.jpg", "a.jpeg", "a.tiff", "a.pdf", "a.gif"] {
        #expect(ShelfActions.isConvertible(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
    }
    for name in ["a.txt", "a.zip", "a", "a.mp4"] {
        #expect(!ShelfActions.isConvertible(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
    }
    #expect(ShelfActions.isArchive(URL(fileURLWithPath: "/tmp/a.ZIP")))
    #expect(!ShelfActions.isArchive(URL(fileURLWithPath: "/tmp/a.txt")))
}
