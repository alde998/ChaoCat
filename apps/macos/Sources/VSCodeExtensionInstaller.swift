import AppKit
import Foundation

final class VSCodeExtensionInstaller: NSObject {
  private let installedBuildKey = "installedVSCodeExtensionForBuild"
  private var isInstalling = false

  func installIfNeeded() {
    guard ProcessInfo.processInfo.environment["CHAOS_CAT_TEST"] != "1",
          let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
          UserDefaults.standard.string(forKey: installedBuildKey) != build else { return }
    install(showResult: false)
  }

  @objc func installFromMenu() {
    install(showResult: true)
  }

  private func install(showResult: Bool) {
    guard !isInstalling else { return }
    guard let vsix = Bundle.main.resourceURL?.appendingPathComponent("VSCode/ChaosCat.vsix"),
          FileManager.default.fileExists(atPath: vsix.path) else {
      if showResult { showAlert("插件文件未找到", "请重新安装 ChaosCat。") }
      return
    }
    guard let code = codeExecutableURL() else {
      if showResult { showAlert("未找到 VS Code", "安装 Visual Studio Code 后，再从小猫菜单安装插件。") }
      return
    }

    isInstalling = true
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let process = Process()
      process.executableURL = code
      process.arguments = ["--install-extension", vsix.path]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      let succeeded: Bool
      do {
        try process.run()
        process.waitUntilExit()
        succeeded = process.terminationStatus == 0
      } catch {
        NSLog("Chaos Cat VS Code extension install failed: %@", error.localizedDescription)
        succeeded = false
      }
      DispatchQueue.main.async {
        guard let self else { return }
        self.isInstalling = false
        if succeeded, let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
          UserDefaults.standard.set(build, forKey: self.installedBuildKey)
        }
        if showResult {
          self.showAlert(succeeded ? "VS Code 插件已安装" : "VS Code 插件安装失败",
                         succeeded ? "如果 VS Code 已打开，请重新启动扩展宿主。" : "请在 VS Code 中从 VSIX 安装，或稍后从小猫菜单重试。")
        }
        NSLog("Chaos Cat VS Code extension install %@", succeeded ? "succeeded" : "failed")
      }
    }
  }

  private func codeExecutableURL() -> URL? {
    let applications = [
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode"),
      URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Visual Studio Code.app")
    ].compactMap { $0 }
    return applications.map { $0.appendingPathComponent("Contents/Resources/app/bin/code") }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  private func showAlert(_ title: String, _ detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
  }
}
