import XCTest
@testable import Nuntius

final class ConstantsTests: XCTestCase {
    func testCloudModelsContainAllTranscriptionModels() {
        let cloudModels = Constants.UnifiedModel.cloudModels()
        let ids = Set(cloudModels.map { $0.id })

        XCTAssertEqual(cloudModels.count, Constants.OpenAI.TranscriptionModel.allCases.count)
        for model in Constants.OpenAI.TranscriptionModel.allCases {
            XCTAssertTrue(ids.contains("openai:\(model.rawValue)"))
        }
        XCTAssertTrue(cloudModels.allSatisfy { $0.isCloud })
    }

    func testUnifiedModelFromLocal() {
        let local = ModelManager.Model(
            id: "base",
            name: "Base",
            description: "Balanced speed/accuracy",
            sizeHint: "~140MB",
            isDownloaded: true,
            isDownloading: false,
            downloadProgress: 1.0
        )

        let unified = Constants.UnifiedModel.fromLocal(local)
        XCTAssertEqual(unified.id, "base")
        XCTAssertEqual(unified.name, "Base")
        XCTAssertEqual(unified.description, "Balanced speed/accuracy")
        XCTAssertEqual(unified.sizeOrCost, "~140MB")
        XCTAssertFalse(unified.isCloud)
        XCTAssertNil(unified.cloudModel)
    }

    func testTranscriptionModelMetadata() {
        XCTAssertEqual(Constants.OpenAI.TranscriptionModel.gpt4oTranscribe.displayName, "GPT-4o Transcribe (Best)")
        XCTAssertEqual(Constants.OpenAI.TranscriptionModel.gpt4oTranscribe.description, "Highest accuracy, $0.006/min")
        XCTAssertEqual(Constants.OpenAI.TranscriptionModel.gpt4oMiniTranscribe.displayName, "GPT-4o Mini Transcribe")
        XCTAssertEqual(Constants.OpenAI.TranscriptionModel.gpt4oMiniTranscribe.description, "Good accuracy, $0.003/min")
        XCTAssertEqual(Constants.OpenAI.TranscriptionModel.whisper1.displayName, "Whisper")
        XCTAssertEqual(Constants.OpenAI.TranscriptionModel.whisper1.description, "Legacy model, $0.006/min")
        XCTAssertEqual(Constants.OpenAI.defaultModel, .gpt4oTranscribe)
    }

    func testLanguagesAreSortedAndContainCommonCodes() {
        let sorted = Constants.sortedLanguages
        XCTAssertTrue(sorted.count > 10)
        XCTAssertTrue(Constants.validLanguageCodes.contains("en"))
        XCTAssertTrue(Constants.validLanguageCodes.contains("es"))
        XCTAssertTrue(Constants.validLanguageCodes.contains("zh"))

        let names = sorted.map { $0.name }
        XCTAssertEqual(names, names.sorted())

        let codes = sorted.map { $0.code }
        XCTAssertEqual(Set(codes).count, codes.count)
    }
}
