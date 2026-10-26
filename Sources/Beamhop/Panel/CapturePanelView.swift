import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BeamhopCore

// CLT SDKs may declare @State without supplying its macro plugin.
private final class CapturePanelViewState: ObservableObject {
    let destinationMenu = DestinationMenuPresenter()
    @Published var originals: Set<String> = []
    @Published var imagePreviews: Set<String> = []
    @Published var projectName = ""
    @Published var newTarget: DeliveryTarget = .clipboard
}

struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    @StateObject private var viewState = CapturePanelViewState()
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Instructions for the agent").foregroundStyle(Color.accentColor)
                    Spacer()
                    Text("Optional · materials only if empty").foregroundStyle(.secondary)
                }.font(.caption)
                TextEditor(text: $model.note)
                    .font(.system(size: 16)).scrollContentBackground(.hidden)
                    .frame(height: min(112, max(50, CGFloat(model.note.components(separatedBy: "\n").count) * 23)))
                    .overlay(alignment: .topLeading) {
                        if model.note.isEmpty {
                            Text("Compare these materials and update the plan…")
                                .font(.system(size: 16)).foregroundStyle(.tertiary)
                                .padding(.leading, 5).padding(.top, 1)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .focused($promptFocused).accessibilityLabel("Instructions for the agent")
                    .accessibilityIdentifier("capture.instruction")
                if model.snapshot.hasNativeCommand {
                    Text("Use / commands in the receiving app. Your text is kept exactly as typed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(L10n.f("Materials · %lld", Int64(model.snapshot.materials.count))).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.onAttachmentAction?() } label: {
                        Label("Add files or images", systemImage: "paperclip")
                    }.buttonStyle(.plain).accessibilityIdentifier("capture.attach")
                }.font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($model.materials) { $material in materialRow($material) }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "plus").foregroundStyle(.secondary).padding(.top, 3)
                            TextEditor(text: $model.additionalText)
                                .scrollContentBackground(.hidden).font(.system(size: 13))
                                .frame(height: min(100, max(28, CGFloat(model.additionalText.components(separatedBy: "\n").count) * 19)))
                                .overlay(alignment: .topLeading) {
                                    if model.additionalText.isEmpty {
                                        Text("Type or paste more material…").foregroundStyle(.tertiary)
                                            .padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                }
                                .accessibilityLabel("Additional material")
                                .accessibilityIdentifier("capture.add-text")
                        }.font(.system(size: 13))
                    }.padding(.vertical, 3)
                }.frame(height: min(220, CGFloat(max(1, model.materials.count)) * 62 + 32))
            }.padding(16)
            if model.isCreating { creation }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if model.pendingImportCount > 0 {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Adding attachments…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    ZStack {
                        DestinationButton(presenter: viewState.destinationMenu, model: model) {
                            model.creatingProject = true; model.isCreating = true
                        }
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((model.selectedTarget ?? model.unavailableTarget)?.displayName ?? L10n.s("Local draft"))
                                    .font(.system(size: 13, weight: .medium))
                                Text([model.workName, model.snapshot.route.sessionLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            Spacer(minLength: 0)
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }.frame(minHeight: 34)
                    Button("Pocket") { model.onOpenPocket?() }.buttonStyle(.plain).font(.caption)
                }
                if model.receiverChanged && !model.rebindAcknowledged {
                    Text("Confirm the receiving app for this work before continuing.").font(.caption).foregroundStyle(.orange)
                }
                PanelCheckbox(title: "Request a conclusion back via MCP", identifier: "capture.result-return",
                              isOn: $model.requestsResultReturn)
                if model.requestsResultReturn {
                    Text("Optional: the receiving agent needs Beamhop MCP. Returned conclusions appear in Inbox and handoff history; they do not verify task completion.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let message = model.draftError ?? model.attachmentWarning {
                    Text(message).font(.caption).foregroundStyle(.orange)
                    if model.attachmentWarning != nil {
                        Button("Copy text · add files in app") { model.onCopyText?() }
                            .font(.caption).disabled(model.pendingImportCount > 0)
                    }
                }
                HStack {
                    Button { model.hold() } label: { Label("Save to Pocket", systemImage: "tray.and.arrow.down") }
                        .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                        .disabled(!model.canHold).keyboardShortcut("5", modifiers: .command)
                    Spacer(minLength: 8)
                    Button(model.confirmLabel) { model.confirm() }
                        .disabled(!model.canConfirm).keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                }
                Text(model.session == .newInApp
                     ? L10n.s("Text will be copied. Create a session in the app, then paste and add attachments.")
                     : model.selectedTarget?.handoffDetail ?? L10n.s("Keep a local record"))
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(14)
        }
        .frame(width: 480).background(.regularMaterial)
        .onAppear { promptFocused = true }
        .onChange(of: model.isCreating) { _, value in
            if value { viewState.projectName = model.creatingProject ? "" : model.workName; viewState.newTarget = model.selectedTarget ?? .clipboard }
        }
        .onExitCommand { if model.isCreating { model.isCreating = false } else { model.cancel() } }
        .onPasteCommand(of: [.fileURL, .png, .tiff]) { _ in model.onPasteAttachments?() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { model.onDropFiles?([url]) }
                }
            }
            return !providers.isEmpty
        }
    }

    @ViewBuilder private func materialRow(_ binding: Binding<HopMaterial>) -> some View {
        let material = binding.wrappedValue
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if material.kind == .image, let path = material.localPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 38, height: 30)
                } else { Image(systemName: material.kind == .text ? "text.quote" : "doc") }
                Text(material.original?.appName ?? (material.kind == .text ? L10n.s("Added text") : material.name))
                    .lineLimit(1).help(material.original?.url ?? material.name)
                if material.isEdited { Text("Edited").foregroundStyle(Color.accentColor) }
                Spacer(minLength: 0)
                if material.original != nil {
                    Button(viewState.originals.contains(material.id) ? L10n.s("Hide original") : L10n.s("View original")) {
                        if !viewState.originals.insert(material.id).inserted { viewState.originals.remove(material.id) }
                    }.buttonStyle(.plain)
                } else if let path = material.localPath {
                    if material.kind == .image {
                        Button("Preview") {
                            if !viewState.imagePreviews.insert(material.id).inserted { viewState.imagePreviews.remove(material.id) }
                        }.buttonStyle(.plain)
                    } else {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            .buttonStyle(.plain)
                    }
                }
                Button { model.materials.removeAll { $0.id == material.id } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.f("Remove %@", material.name))
            }.font(.caption2).foregroundStyle(.secondary)
            if material.kind == .text {
                TextEditor(text: binding.text)
                    .scrollContentBackground(.hidden).font(.system(size: 13))
                    .frame(height: min(140, max(42, CGFloat(material.text.components(separatedBy: "\n").count) * 19)))
                    .accessibilityLabel("Material text")
                    .accessibilityIdentifier("capture.material.\(material.id)")
            } else {
                Text(ByteCountFormatter.string(fromByteCount: material.byteCount ?? 0, countStyle: .file))
                    .font(.caption2).foregroundStyle(.secondary)
                if viewState.imagePreviews.contains(material.id), let path = material.localPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                }
            }
            if viewState.originals.contains(material.id), let original = material.originalText {
                VStack(alignment: .leading, spacing: 4) {
                    if let url = material.original?.url { Text(url).font(.caption2).textSelection(.enabled) }
                    Text(original).font(.caption).textSelection(.enabled)
                    Button("Restore original") { binding.wrappedValue.text = original }.font(.caption)
                }.padding(8).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    private var creation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.creatingProject ? L10n.s("New project") : L10n.s("New session")).font(.headline)
                Spacer()
                Button("Cancel") { model.isCreating = false }.buttonStyle(.plain)
            }
            if model.creatingProject {
                TextField("Project name", text: $viewState.projectName).textFieldStyle(.roundedBorder)
            } else {
                Picker("Project", selection: $viewState.projectName) {
                    Text("No project").tag("")
                    ForEach(model.projects, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("Receiving app", selection: $viewState.newTarget) {
                ForEach(model.visibleTargets.filter { model.creatingProject || ($0 != .clipboard && $0 != .cowork) }, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            Text("Projects organize material locally. New conversations are created in the receiving app; this does not send anything.")
                .font(.caption).foregroundStyle(.secondary)
            Button(model.creatingProject ? L10n.s("Create project and select") : L10n.s("Use new session in app")) {
                let route = HopRoute(target: viewState.newTarget, project: viewState.projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                                     session: model.creatingProject ? .currentWindow : .newInApp)
                model.onRememberRoute?(route)
                guard model.draftError == nil else { return }
                model.chooseRoute(route); model.isCreating = false
            }.disabled(model.creatingProject && viewState.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(14).background(Color.secondary.opacity(0.04))
    }
}
