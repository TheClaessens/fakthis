import SwiftUI
import Fakthis

/// What the window is before Generate: one field sized to a spoken brain-dump, the Material
/// that
/// produced it as chips on the composer, and Generate.
///
/// There is no Submit — absent, not disabled, because a disabled Submit still answers "can I
/// submit yet?". There is no Ticket type control: the agent infers the type at Generate, and a
/// Story/Bug/Chore control over an empty field turns that proposal into a correction. There is no
/// conversation column and no collapsed spine; before Generate that column does not exist.
struct FrontDoor: View {
    var model: WindowModel
    /// The editing buffer for `Session`'s field. Every edit goes straight in as an intent, and a
    /// field `Session` changed for its own reasons — a take the transcriber appended — is adopted
    /// back, so the PM reads the words before Generate ever sees them.
    @State private var brainDump = ""
    @State private var pushesInFlight = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                composer
                    .frame(width: 660)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    }
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
                    .materialIntake(attach: attach)
            }
        }
        .onAppear { brainDump = model.field }
        .onChange(of: brainDump) { _, typed in
            pushesInFlight += 1
            Task {
                await model.typeBrainDump(typed)
                pushesInFlight -= 1
            }
        }
        .onChange(of: model.field) { _, field in
            // Only while the composer is quiet. A state that arrived mid-keystroke is behind
            // what has been typed, and adopting it would undo the typing.
            guard pushesInFlight == 0, field != brainDump else { return }
            brainDump = field
        }
    }

    // MARK: - Toolbar

    /// With no rail before Generate, Batch and Rewrite have nowhere to live, so they are two
    /// toolbar buttons. You choose the surface before you have anything to put on it. Both are
    /// wired by their own tickets.
    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(Color.accentColor)
            Text(model.projectKey).font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Batch", systemImage: "list.bullet.rectangle") {}
            Button("Improve existing", systemImage: "arrow.triangle.2.circlepath") {}
        }
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What is the work?")
                .font(.system(size: 15, weight: .semibold))

            /// Sixty spoken words, not a column-height box. A field the height of the window
            /// makes it look like Fakthis is waiting for an essay.
            BrainDumpField(text: $brainDump, attach: attach)
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .overlay(alignment: .topLeading) {
                    if brainDump.isEmpty {
                        Text("Say what the work is. Drop, paste or attach what produced it.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }

            chips

            HStack {
                Spacer()
                Button {
                    Task { await model.generate() }
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canGenerate)
            }
        }
        .padding(18)
        .overlay {
            if model.generating {
                ProgressView().controlSize(.large)
            }
        }
    }

    /// Material sits **on** the composer, because that is what Material is — the raw stuff
    /// that
    /// produced this dump, not a browsable rail.
    private var chips: some View {
        HStack(spacing: 7) {
            ForEach(Array(model.material.enumerated()), id: \.offset) { _, item in
                Label(item.filename, systemImage: item.glyph)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(Capsule())
            }
            Button("Attach", systemImage: "paperclip") {
                attach(MaterialIntake.openPanel())
            }
            .buttonStyle(.accessoryBar)
            Spacer()
        }
    }

    private var canGenerate: Bool {
        !model.generating
            && !brainDump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func attach(_ material: [Fakthis.Material]) {
        Task {
            for item in material {
                await model.perform(.attachMaterial(item))
            }
        }
    }
}
