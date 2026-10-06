import ArgumentParser

@main
struct PDMask: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdmask",
        abstract: "画像に写った個人情報をオンデバイスで検出して黒塗りする。",
        subcommands: [
            MaskCommand.self,
            DetectCommand.self
        ]
    )
}
