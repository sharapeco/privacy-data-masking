import FoundationModels

public enum FoundationModelsAvailability {
    public static func requireAvailable() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(.deviceNotEligible):
            throw PDMaskError("この Mac は Apple Intelligence に対応していません。")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw PDMaskError("Apple Intelligence が無効です。システム設定 > Apple Intelligence と Siri で有効にしてから再実行してください。")
        case .unavailable(.modelNotReady):
            throw PDMaskError("オンデバイスモデルを準備中です。しばらく待ってから再実行してください。")
        case .unavailable:
            throw PDMaskError("オンデバイス言語モデルが利用できません（理由不明）。")
        }
    }
}
