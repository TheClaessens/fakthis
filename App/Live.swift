import Foundation
import Fakthis

/// The real world behind `Session`: Keychain for the two secrets, Jira over REST, the bundled
/// transcriber on the ANE, and the Application Support tree in §4.
///
/// Nothing here is canned. What used to be a fixture Project is now first launch: the app opens
/// with no credentials and no Project, and the PM enters both.
enum Live {
    /// §4. Not Documents, not iCloud, not the bundle.
    static func applicationSupport() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appending(component: "Fakthis")
    }

    static func open() -> Session {
        // Two Keychain items keyed off the bundle ID (§3.1). `swift run` has no bundle
        // identifier, so the same string stands in — the items are the app's either way.
        let secrets = KeychainSecrets(bundleID: Bundle.main.bundleIdentifier ?? "dev.fakthis.app")
        let credentials = Credentials(secrets: secrets)
        return Session(
            applicationSupport: applicationSupport(),
            model: ModelHTTP(
                access: { try await credentials.model() },
                send: { try await URLSession.shared.data(for: $0) }
            ),
            jira: JiraCloud(
                credentials: { try await credentials.jira() },
                send: { try await URLSession.shared.data(for: $0) }
            ),
            // Weights ship in the app bundle and download nothing on first run (§2). Without
            // them the engines fail to load and voice does not work — which is #36's business,
            // not this ticket's; the compile status is honest either way.
            transcriber: BundledTranscriber.production(
                models: Bundle.main.resourceURL ?? Bundle.main.bundleURL
            ),
            secrets: secrets,
            settingsChanged: { await credentials.use($0) }
        )
    }
}

/// What the two network adapters read at the call. Neither the Jira site nor the model id exists
/// when the app starts for the first time — the PM types them into a window that is already
/// running — so the adapters are built once and this is what changes underneath them.
///
/// It is not a second copy of the settings anyone reads. `Session` owns them and tells this
/// what they are; nothing in the window asks this what the site is.
actor Credentials {
    private var settings: Settings?
    private let secrets: any Secrets

    init(secrets: any Secrets) {
        self.secrets = secrets
    }

    func use(_ settings: Settings?) {
        self.settings = settings
    }

    /// Before first launch there is no site to call, which reads to `Session` the same way a
    /// site that will not answer does: the press does nothing and nothing is lost (§15).
    func jira() async throws -> JiraCredentials {
        guard let settings else { throw JiraUnreachable() }
        return JiraCredentials(
            host: settings.site,
            email: settings.email,
            apiToken: try await secrets.jiraToken()
        )
    }

    func model() async throws -> ModelAccess {
        guard let settings else { throw ModelFailed() }
        return ModelAccess(
            endpoint: ModelProvider(stored: settings.provider).completions,
            modelId: settings.modelId,
            apiKey: try await secrets.modelKey()
        )
    }
}
