import SymphonyServerCore
import SymphonyShared

// MARK: - Provider Adapter Factory

public enum ProviderAdapterFactory {
  public static func makeAdapter(
    for provider: ProviderName,
    config: ProvidersConfig,
    processLauncher: ProcessLaunching? = nil
  ) -> any ProviderAdapting {
    switch provider {
    case .codex:
      return CodexAdapter(config: config.codex, processLauncher: processLauncher)
    case .claudeCode:
      return ClaudeCodeAdapter(config: config.claudeCode, processLauncher: processLauncher)
    case .copilotCLI:
      return CopilotCLIAdapter(config: config.copilotCLI, processLauncher: processLauncher)
    }
  }
}
