import SwiftUI
import VehlaNativeUISDK

struct CaptureHubWorkspaceView: View {
    @ObservedObject var theme: ThemeBox

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 28, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture Hub")
                        .font(.title2.weight(.semibold))
                    Text("Use these actions from QuickGlass on selected text.")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(CaptureHubActionCatalog.all, id: \.rawValue) { action in
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

            Divider()
            Text("Reminders and events need full system access. Notes actions need Automation access to Apple Notes.")
                .font(.caption)
                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
            Text("This workspace is a reference card; captures run only from QuickGlass.")
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
