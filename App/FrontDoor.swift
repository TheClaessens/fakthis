import SwiftUI
import Fakthis

/// What the window is before Generate: one field sized to a spoken brain-dump, the Material
/// that produced it as chips on the composer, and Generate. Voice is an input method into that
/// same field — Speak toggles a take that appends — and Generate stays a separate press.
///
/// There is no Submit — absent, not disabled, because a disabled Submit still answers "can I
/// submit yet?". There is no Ticket type control: the agent infers the type at Generate, and a
/// Story/Bug/Chore control over an empty field turns that proposal into a correction. There is no
/// conversation column and no collapsed spine; before Generate that column does not exist.
struct FrontDoor: View {
    var model: WindowModel

    @State private var showingProjects = false
    @State private var showingTerms = false
    @State private var reading = false
    /// The key field is a front-door surface, not a sheet: Batch and Rewrite are toolbar
    /// buttons until a Draft exists, and this is what Rewrite's button opens.
    @State private var improvingExisting = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    if improvingExisting {
                        ImproveExisting(
                            model: model,
                            cancel: { improvingExisting = false }
                        )
                    } else {
                        SessionField(model: model) { brainDump in
                            composer(brainDump)
                        }
                        .materialIntake(attach: attach)
                    }
                }
                .frame(width: 660)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
            }
        }
        .sheet(isPresented: $showingProjects) {
            ProjectList(model: model, close: { showingProjects = false })
        }
        .sheet(isPresented: $showingTerms) {
            ProjectTerms(model: model, close: { showingTerms = false })
        }
        .alert("Text Material", isPresented: disclosure) {
            Button("OK") {}
        } message: {
            Text(model.textMaterialDisclosure ?? "")
        }
    }

    /// The disclosure's second moment: the first text Material added to this Project. It is an
    /// alert because it is an event — read once, pressed through, gone — and the one thing §3.5
    /// forbids is a warning that lives on the Draft. The proposal screen carries the first
    /// moment, so while one is up this does not say the same thing twice.
    ///
    /// Dismissing is the acknowledgement, whichever way it is dismissed. `reading` holds the
    /// alert shut across the round trip to `Session`, because a binding that still reads true
    /// after SwiftUI closes the alert puts it straight back up.
    private var disclosure: Binding<Bool> {
        Binding(
            get: {
                model.textMaterialDisclosure != nil && model.proposedProject == nil && !reading
            },
            set: { showing in
                guard !showing else { return }
                reading = true
                Task {
                    await model.perform(.acknowledgeTextMaterialDisclosure)
                    reading = false
                }
            }
        )
    }

    // MARK: - Toolbar

    /// With no rail before Generate, Batch and Rewrite have nowhere to live, so they are two
    /// toolbar buttons. You choose the surface before you have anything to put on it. Batch is
    /// still its own ticket; Rewrite's button opens the key field.
    ///
    /// The Project key is the third: everything that belongs to the Project rather than to this
    /// Draft — its terms, the other Projects, adding one — hangs off the name of the Project you
    /// are in, and none of it reaches the Draft column.
    private var toolbar: some View {
        HStack(spacing: 10) {
            project
            Spacer()
            Group {
                Button("Batch", systemImage: "list.bullet.rectangle") {}
                Button("Improve existing", systemImage: "arrow.triangle.2.circlepath") {
                    improvingExisting = true
                }
            }
            .buttonStyle(.accessoryBar)
            .disabled(model.working)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var project: some View {
        Menu {
            Button("Project terms…") { showingTerms = true }
            Divider()
            Button("Projects…") { showingProjects = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                Text(model.projectKey).font(.system(size: 13, weight: .semibold))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .fixedSize()
    }

    // MARK: - Composer

    private func composer(_ brainDump: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VoiceStrip(model: model, gesture: "Press to start / stop")
            VStack(alignment: .leading, spacing: 12) {
                Text("What is the work?")
                    .font(.system(size: 15, weight: .semibold))

                /// Sixty spoken words, not a column-height box. A field the height of the window
                /// makes it look like Fakthis is waiting for an essay.
                BrainDumpField(text: brainDump, attach: attach)
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    }
                    .overlay(alignment: .topLeading) {
                        if brainDump.wrappedValue.isEmpty {
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
                    SpeakToggle(model: model)
                    Spacer()
                    Button {
                        Task { await model.generate() }
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canGenerate(brainDump.wrappedValue))
                }
            }
            .padding(18)
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

    private func canGenerate(_ brainDump: String) -> Bool {
        !model.working
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
