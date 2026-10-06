import Testing
@testable import PDMaskCore

@Suite struct ChunkingTests {
    @Test func shortInputIsOneChunk() {
        #expect(PIIClassifier.chunkRanges(lineLengths: Array(repeating: 10, count: 15)) == [0..<15])
    }

    @Test func emptyInputHasNoChunks() {
        #expect(PIIClassifier.chunkRanges(lineLengths: []).isEmpty)
    }

    @Test func longInputOverlapsByTwoLines() {
        let ranges = PIIClassifier.chunkRanges(lineLengths: Array(repeating: 10, count: 100))
        #expect(ranges.first == 0..<40)
        #expect(ranges.dropFirst().first == 38..<78)
        #expect(ranges.last?.upperBound == 100)
    }

    @Test func characterLimitSplitsChunks() {
        let ranges = PIIClassifier.chunkRanges(lineLengths: Array(repeating: 500, count: 6))
        #expect(ranges.allSatisfy { $0.count <= 3 })
        #expect(ranges.last?.upperBound == 6)
    }

    @Test func oversizedLineStillProgresses() {
        let ranges = PIIClassifier.chunkRanges(lineLengths: [5000, 5000, 5000])
        #expect(ranges == [0..<1, 1..<2, 2..<3])
    }
}
