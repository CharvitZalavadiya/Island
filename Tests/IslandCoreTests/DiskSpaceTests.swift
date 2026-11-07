import Testing
import Foundation
@testable import IslandCore

@Test func diskSpaceOfTheHomeFolderIsSensible() throws {
    let space = try #require(DiskSpace.read(at: FileManager.default.homeDirectoryForCurrentUser))
    #expect(space.totalBytes > 0)
    #expect(space.availableBytes <= space.totalBytes)
}

@Test func diskSpaceOfAMissingPathIsNil() {
    #expect(DiskSpace.read(at: URL(fileURLWithPath: "/definitely/not/here/at/all")) == nil)
}

@Test func theUsedFractionIsWhatIsNotAvailable() {
    #expect(DiskSpace(availableBytes: 25, totalBytes: 100).usedFraction == 0.75)
    #expect(DiskSpace(availableBytes: 0, totalBytes: 100).usedFraction == 1)
    #expect(DiskSpace(availableBytes: 100, totalBytes: 0).usedFraction == 0)
    #expect(DiskSpace(availableBytes: 200, totalBytes: 100).usedFraction == 0)
}

@Test func storageIsFormatted() {
    #expect(StatsFormat.storage(DiskSpace(availableBytes: 128_400_000_000, totalBytes: 494_400_000_000)) == "128.4 GB free of 494.4 GB")
    #expect(StatsFormat.storage(DiskSpace(availableBytes: 1_500_000_000_000, totalBytes: 2_000_000_000_000)) == "1.50 TB free of 2.00 TB")
    #expect(StatsFormat.storage(DiskSpace(availableBytes: 850_000_000, totalBytes: 494_400_000_000)) == "850 MB free of 494.4 GB")
    #expect(StatsFormat.storage(DiskSpace(availableBytes: 0, totalBytes: 494_400_000_000)) == "0 MB free of 494.4 GB")
}

@Test func perAppMemoryUsesMBBelowAGigabyte() {
    #expect(StatsFormat.appMemory(512 * 1_048_576) == "512 MB")
    #expect(StatsFormat.appMemory(0) == "0 MB")
    #expect(StatsFormat.appMemory(UInt64(2.5 * 1_073_741_824)) == "2.5 GB")
}

@Test func perAppCPUShowsOneDecimal() {
    #expect(StatsFormat.appCPU(41.84) == "41.8%")
    #expect(StatsFormat.appCPU(0) == "0.0%")
    #expect(StatsFormat.appCPU(250) == "250.0%")
}

@Test func theStoragePillSaysWhatIsFreeAndHowMuchIsUsed() {
    let space = DiskSpace(availableBytes: 13_600_000_000, totalBytes: 245_100_000_000)
    #expect(StatsFormat.storageFree(space) == "13.6 GB Free")
    #expect(StatsFormat.storageUsed(space) == "232 GB / 245 GB used")
    #expect(StatsFormat.storageUsed(DiskSpace(availableBytes: 0, totalBytes: 500_000_000_000)) == "500 GB / 500 GB used")
    #expect(StatsFormat.storageFree(DiskSpace(availableBytes: 850_000_000, totalBytes: 500_000_000_000)) == "850 MB Free")
}
