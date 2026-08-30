import SwiftUI
import Fakthis

/// First launch: what Fakthis needs once, for the whole app.
///
/// Two things share the screen because they share the moment. The Neural Engine compiles the
/// transcriber the first time Fakthis runs, and that can stall — so the screen says it is
/// happening rather than letting the app read as frozen, and Save waits for it. Nothing here
/// pretends to be ready before it is (§3.1).
///
/// The credentials are **app-level**: a Project is a Jira project key on this site, not a second
/// token. Both secrets go to Keychain and neither is ever written next to a Draft (§3.2).
struct Setup: View {
    var model: WindowModel

    /// Six empty fields and nothing else to do: the first one is where the PM was going anyway.
    @FocusState private var typingSite: Bool

    @State private var site = ""
    @State private var email = ""
    @State private var jiraToken = ""
    @State private var provider = ModelProvider.openAI
    @State private var modelId = ModelProvider.defaultModelId
    @State private var modelKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                if model.aneCompileInProgress { compiling }
                form
                save
            }
            .frame(width: 520)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
            .background(Color.windowGround)
            .task { typingSite = true }
            .task { await model.waitForANECompile() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Set up Fakthis")
                .font(.system(size: 21, weight: .semibold))
            Text("Once, for every Project on this Jira site.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }

    private var compiling: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("The Neural Engine is compiling the transcriber.")
                    .font(.system(size: 12, weight: .medium))
                Text("It happens once. Fakthis is not ready until it finishes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Jira") {
                    labelled("Site") {
                        TextField("your-team.atlassian.net", text: $site)
                            .focused($typingSite)
                    }
                labelled("Email") {
                    TextField("you@company.com", text: $email)
                }
                labelled("API token") {
                    SecureField("", text: $jiraToken)
                }
            }
            section("Model") {
                labelled("Provider") {
                    Picker("", selection: $provider) {
                        ForEach(ModelProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .labelsHidden()
                }
                    labelled("Model id") {
                        TextField(ModelProvider.defaultModelId, text: $modelId)
                    }
                labelled("API key") {
                    SecureField("", text: $modelKey)
                }
            }
            Text(
                "The API token and the model key go to your macOS Keychain. "
                    + "Neither is written next to your Drafts, and neither ships in the app."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var save: some View {
        HStack {
            Spacer()
            Button("Save") {
                Task {
                        await model.saveCredentials(
                            Settings(
                                site: site,
                                email: email.trimmingCharacters(in: .whitespaces),
                            provider: provider.rawValue,
                            modelId: modelId.trimmingCharacters(in: .whitespaces)
                        ),
                        jiraToken: jiraToken,
                        modelKey: modelKey
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        !model.working && !model.aneCompileInProgress
            && ![site, email, jiraToken, modelId, modelKey].contains {
                $0.trimmingCharacters(in: .whitespaces).isEmpty
            }
    }

    // MARK: - Shape

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
            content()
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
        }
    }
}
