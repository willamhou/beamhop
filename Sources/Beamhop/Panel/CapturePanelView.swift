import SwiftUI
import BeamhopCore

// Keep view-local state compatible with CLT SDKs that declare @State as a macro
// without shipping SwiftUIMacros. StateObject preserves the same per-view lifetime.
private final class CapturePanelViewState: ObservableObject {
    @Published var naming = false
    let destinationMenu = DestinationMenuPresenter()
}

/// The default surface is one handoff. Other receivers are disclosed only on request.
struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel
    @StateObject private var viewState = CapturePanelViewState()
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                    Text(model.capture.appName)
                    if let url = model.capture.url, let host = URL(string: url)?.host {
                        Text("· \(host)").lineLimit(1)
                    }
                    Spacer()
                    Text("Beamhop").foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(model.previewText ?? model.capture.windowTitle ?? L10n.s("Captured material"))
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ZStack {
                DestinationButton(presenter: viewState.destinationMenu, model: model) { viewState.naming = true }
                HStack(spacing: 10) {
                    Image(systemName: model.selectedTarget == nil ? "tray" : "arrow.up.forward.app")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.destinationTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if !model.workName.isEmpty, let target = model.selectedTarget {
                            Text(target.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(model.unavailableTarget != nil
                             ? L10n.s("Unavailable · choose another destination or hold for later")
                             : model.selectedTarget?.handoffDetail ?? L10n.s("Keep a local record"))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)

            if viewState.naming {
                TextField("Name this work", text: $model.workName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewState.naming = false }
            }
            if model.receiverChanged && !model.rebindAcknowledged {
                Text("Confirm the receiving app for this work before continuing.")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("Add a note, if needed", text: $model.note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .focused($noteFocused)
                .onSubmit { model.confirm() }
                .accessibilityLabel("Note")

            Divider()
            HStack {
                Button { model.hold() } label: {
                    Label("Hold for later", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("5", modifiers: .command)
                .disabled(!model.canHold)
                Spacer()
                Button(model.confirmLabel) { model.confirm() }
                    .disabled(!model.canConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial)
        .onAppear { noteFocused = true }
        .onExitCommand { model.cancel() }
        .background {
            Button("Cancel") { model.cancel() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }
}
