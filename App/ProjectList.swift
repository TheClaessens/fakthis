import SwiftUI
import Fakthis

/// The local Projects, and the key field that adds one. A Project is a folder under Application
/// Support named by its Jira key (§3.3) — there is no Jira browser here, no board and no sprint
/// list, because Fakthis is a writer and not a Jira client.
///
/// Opening one lands on the **front door**. There is no Project home in between: the window is
/// the field, the Material and Generate, and nothing about a Project needs a surface of its own.
///
/// The same view is the window when no Project is open and a sheet when one is, because choosing
/// a Project and adding one are the same two things either way.
struct ProjectList: View {
    var model: WindowModel
    /// Absent when this is the window rather than a sheet — there is nothing to go back to.
    var close: (() -> Void)?

    @State private var key = ""
    /// Adding the first Project is the only thing to do on this screen when it is the window,
    /// and it is what a PM came to the sheet for often enough to be worth the same head start.
    @FocusState private var typingKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading
            if let proposed = model.proposedProject {
                ProjectProposal(model: model, proposed: proposed, added: close)
            } else {
                projects
                add
            }
        }
        .frame(width: 440)
        .padding(.horizontal, 32)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.windowGround)
        .task { typingKey = true }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Projects")
                    .font(.system(size: 21, weight: .semibold))
                Text("One Fakthis Project for one Jira project key.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let close {
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var projects: some View {
        if model.projects.isEmpty {
            Text("No Projects yet. Add the Jira project you write Tickets in.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        } else {
            VStack(spacing: 0) {
                ForEach(model.projects, id: \.self) { key in
                    row(key)
                    if key != model.projects.last { Divider() }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ key: String) -> some View {
        Button {
            Task {
                await model.perform(.openProject(key))
                close?()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(key == model.projectKey ? Color.accentColor : .secondary)
                Text(key).font(.system(size: 13, weight: .medium))
                Spacer()
                if key == model.projectKey {
                    Text("Open")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(model.working)
    }

    private var add: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a Project")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Jira project key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                    .focused($typingKey)
                    .onSubmit(enterKey)
                Button("Add", action: enterKey)
                    .disabled(model.working || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if model.projectKeyRefused {
                Text("Jira did not answer for that key. Nothing was added — try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func enterKey() {
        let entered = key.trimmingCharacters(in: .whitespaces).uppercased()
        guard !entered.isEmpty else { return }
        Task { await model.enterProjectKey(entered) }
    }
}

/// The mapping the PM confirms. Fakthis's three Ticket types are its own (ADR-0004); what a Jira
/// project offers is whatever it happens to offer. So the discovered standard issue types are on
/// screen against Story, Bug and Chore, every one of them overridable, and three Ticket types on
/// one Jira issue type is a legal answer — a project with a single standard type still gets three
/// templates. Fakthis never creates a Jira issue type; there is nothing here that could.
///
/// The disclosure that text Material goes to the model provider sits on this screen because this
/// is the screen being confirmed (§3.5). It is read here, and again the first time text Material
/// is added — never on the Draft.
struct ProjectProposal: View {
    var model: WindowModel
    var proposed: ProposedProject
    /// The new Project is open the moment it is confirmed, so a sheet has done its job and goes.
    /// Absent when the list is the window: there the front door takes over by itself.
    var added: (() -> Void)?

    @State private var mapping: [TicketType: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add \(proposed.key)")
                    .font(.system(size: 15, weight: .semibold))
                Text(
                    "Jira issue types in this project: "
                        + proposed.standardJiraIssueTypes.joined(separator: ", ")
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(TicketType.allCases, id: \.self) { ticketType in
                    HStack(spacing: 12) {
                        Text(ticketType.label)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 66, alignment: .trailing)
                        Picker("", selection: binding(ticketType)) {
                            ForEach(proposed.standardJiraIssueTypes, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            Text(
                "Fakthis maps its Story, Bug and Chore onto Jira issue types this project "
                    + "already has. It never creates one, and more than one may map onto the "
                    + "same Jira issue type."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let disclosure = model.textMaterialDisclosure {
                Label(disclosure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel") {
                    Task { await model.perform(.dismissProposedProject) }
                }
                Spacer()
                Button("Add \(proposed.key)") {
                    Task {
                        await model.confirmProject(mapping: mapping)
                        if model.projectKey == proposed.key { added?() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.working || mapping.count < TicketType.allCases.count)
            }
        }
        .task(id: proposed.key) { mapping = proposed.mapping }
        .overlay {
            if model.working {
                ProgressView().controlSize(.large)
            }
        }
    }

    private func binding(_ ticketType: TicketType) -> Binding<String> {
        Binding(
            get: { mapping[ticketType] ?? proposed.mapping[ticketType] ?? "" },
            set: { mapping[ticketType] = $0 }
        )
    }
}
