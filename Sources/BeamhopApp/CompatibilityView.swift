import SwiftUI

struct CompatibilityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compatibility Matrix")
                    .font(.largeTitle.weight(.semibold))
                Text("公开当前版本的验证边界。unknown / unverified 目标会安全降级到剪贴板。")
                    .foregroundStyle(.secondary)
            }
            .padding(26)

            Divider()

            if !model.compatibility.snapshot.sourceAvailable {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "questionmark.diamond")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("内置 Matrix 不可用")
                            .font(.headline)
                        Text(model.compatibility.snapshot.sourceDescription)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                Divider()
            }

            List(model.compatibility.snapshot.records) { record in
                CompatibilityRow(record: record) {
                    model.compatibility.markLocalSuccess(recordID: record.id)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                if let schema = model.compatibility.snapshot.schemaVersion {
                    Text("schema v\(schema)")
                }
                if let generated = model.compatibility.snapshot.generatedAt {
                    Text("generated \(generated)")
                }
                Spacer()
                Text("本地标记仅保存版本号，不包含 Capture 内容")
                Button("重新加载") { model.compatibility.reload() }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 520)
    }
}

private struct CompatibilityRow: View {
    let record: CompatibilityRecord
    let markSuccess: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(record.confidence.color)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title)
                        .font(.body.weight(.semibold))
                    Text(record.confidence.label)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(record.confidence.color)
                    Spacer()
                    if let installed = record.installedVersion {
                        Text("installed \(installed)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(record.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !record.testedVersions.isEmpty {
                    Text("tested: \(record.testedVersions.joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            if record.installedVersion != nil {
                Button("本机成功") { markSuccess() }
                    .help("仅在本机记录此版本工作正常；Phase 2 才会开放上报通道")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(record.confidence.label)
    }
}
