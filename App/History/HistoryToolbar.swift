import AppKit
import SwiftUI
import UsageCore

/// Title bar row: title, account picker, range segmented control, Export Data menu (⌥ = all accounts).
struct HistoryToolbar: View {
    @Bindable var model: HistoryModel

    var body: some View {
        HStack(spacing: 10) {
            Text("Usage History").font(.system(size: 13, weight: .semibold))
            Spacer()
            accountMenu
            Picker("", selection: $model.range) {
                ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            exportMenu
        }
        .padding(.leading, 80)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(.bar)
    }

    private static var option: Bool { NSEvent.modifierFlags.contains(.option) }

    private var current: AccountEntry? { model.entries.first { $0.id == model.account } }

    private var accountMenu: some View {
        HStack(spacing: 6) {
            glyph(current?.kind ?? .claude)
            Picker("", selection: $model.account) {
                if model.entries.isEmpty { Text("No accounts").tag(AccountID?.none) }
                ForEach(model.entries, id: \.id) { e in Text(e.displayName).tag(AccountID?.some(e.id)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .disabled(model.entries.isEmpty)
    }

    private func glyph(_ k: ProviderKind) -> some View {
        Text(k == .claude ? "C" : "G")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(RoundedRectangle(cornerRadius: 4).fill(GlassStyle.accent(k)))
    }

    private var exportMenu: some View {
        Menu("Export Data") {
            Button("Export as CSV…") { model.export(.csv, allAccounts: Self.option) }
            Button("Export as JSON…") { model.export(.json, allAccounts: Self.option) }
            Divider()
            Text("Hold ⌥ when choosing to export all accounts")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(model.store == nil || model.entries.isEmpty)
    }
}
