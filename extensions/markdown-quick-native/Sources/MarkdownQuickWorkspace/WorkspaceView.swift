import SwiftUI
import VehlaNativeUISDK

struct MarkdownQuickWorkspaceView: View {
    @ObservedObject var theme: ThemeBox

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "text.justify.left")
                    .font(.system(size: 28, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Markdown Quick")
                        .font(.title2.weight(.semibold))
                    Text("Use these actions from QuickGlass on selected Markdown.")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(MarkdownQuickActionCatalog.all, id: \.rawValue) { action in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: action.systemImage)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.headline)
                            Text("Runs entirely on this Mac.")
                                .font(.caption)
                                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
                        }
                        Spacer()
                    }
                }
            }

            Text("The Store requires a workspace, but Markdown Quick is built for QuickGlass.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: theme.theme.backgroundColor))
        .foregroundStyle(Color(nsColor: theme.theme.primaryTextColor))
        .preferredColorScheme(theme.theme.isDark ? .dark : .light)
    }
}
