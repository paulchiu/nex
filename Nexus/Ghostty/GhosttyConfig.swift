import Foundation

/// Type-safe wrapper around ghostty_config_t.
final class GhosttyConfig {
    let rawConfig: ghostty_config_t

    init() {
        rawConfig = ghostty_config_new()
        ghostty_config_load_default_files(rawConfig)
    }

    func finalize() {
        ghostty_config_finalize(rawConfig)
    }

    deinit {
        ghostty_config_free(rawConfig)
    }
}
