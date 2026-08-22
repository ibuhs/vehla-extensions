import SwiftUI
import VehlaNativeUISDK

enum ReadingToolsWorkspaceContent: Equatable {
    case reference
    case largeType(String)

    static func from(_ request: VehlaWorkspaceLaunchRequest) -> Self {
        guard request.payload["quickGlassActionID"] == ReadingToolsActionID.largeType.rawValue else {
            return .reference
        }
        let selectedText = request.payload["selectedText"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? request.query
        return .largeType(selectedText)
    }
}

struct ReadingToolsWorkspaceView: View {
    @ObservedObject var theme: ThemeBox
    let content: ReadingToolsWorkspaceContent

    var body: some View {
        Group {
            switch content {
            case .reference:
                referenceView
            case .largeType(let text):
                largeTypeView(text)
            }
        }
        .background(Color(nsColor: theme.theme.backgroundColor))
        .foregroundStyle(Color(nsColor: theme.theme.primaryTextColor))
        .preferredColorScheme(theme.theme.isDark ? .dark : .light)
    }

    private var referenceView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading Tools")
                        .font(.title2.weight(.semibold))
                    Text("Use these actions from QuickGlass on selected text.")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ReadingToolsActionCatalog.all, id: \.rawValue) { action in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: action.systemImage)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.headline)
                            Text(action.caption)
                                .font(.caption)
                                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
                        }
                        Spacer()
                    }
                }
            }

            Text("The Store requires a workspace, but Reading Tools is built for QuickGlass.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func largeTypeView(_ text: String) -> some View {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ScrollView(.vertical) {
            VStack {
                Spacer(minLength: 24)
                Text(isEmpty ? "No selected text." : text)
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(
                        isEmpty
                            ? Color(nsColor: theme.theme.secondaryTextColor)
                            : Color(nsColor: theme.theme.primaryTextColor)
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
