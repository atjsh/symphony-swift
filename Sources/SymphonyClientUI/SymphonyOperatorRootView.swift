import SwiftUI
import SymphonyShared

public struct SymphonyOperatorRootView: View {
    @ObservedObject var model: SymphonyOperatorModel

    public init(model: SymphonyOperatorModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionCard
                    issuesSection
                }
                .padding(20)
            }
            .navigationTitle("Symphony")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    issueDetailSection
                    runDetailSection
                    logsSection
                }
                .padding(20)
            }
            .navigationTitle("Operator")
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.title2.weight(.semibold))

            HStack {
                TextField("Host", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $model.portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
            }

            HStack {
                Button(model.isConnecting ? "Connecting…" : "Connect", action: triggerConnect)
                .disabled(model.isConnecting)

                Button(model.isRefreshing ? "Refreshing…" : "Refresh", action: triggerRefresh)
                .disabled(model.isRefreshing || model.isConnecting)
            }

            if let health = model.health {
                Text("Connected to \(health.trackerKind) via \(model.host):\(model.portText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Default endpoint: localhost:8080")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let connectionError = model.connectionError {
                Text(connectionError)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Issues")
                .font(.title3.weight(.semibold))

            if model.issues.isEmpty {
                Text("No issues loaded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.issues, id: \.issueID.rawValue) { issue in
                    Button(action: makeIssueSelectionAction(for: issue)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(issue.identifier.rawValue)
                                    .font(.headline)
                                Spacer()
                                if let provider = issue.currentProvider {
                                    ProviderBadge(label: provider)
                                }
                            }

                            Text(issue.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Text("\(issue.state) • \(issue.issueState)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(model.selectedIssueID == issue.issueID ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var issueDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Issue Detail")
                .font(.title3.weight(.semibold))

            if let detail = model.issueDetail {
                Text(detail.issue.title)
                    .font(.title2.weight(.semibold))

                Text(detail.issue.identifier.rawValue)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let description = detail.issue.description {
                    Text(description)
                }

                if let workspacePath = detail.workspacePath {
                    Text(workspacePath)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let latestRun = detail.latestRun {
                    Button(action: makeRunSelectionAction(for: latestRun.runID)) {
                        HStack {
                            Text("Latest Run")
                            Spacer()
                            ProviderBadge(label: latestRun.provider)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Select an issue to inspect its workspace, runs, and sessions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Detail")
                .font(.title3.weight(.semibold))

            if let runDetail = model.runDetail {
                HStack {
                    Text(runDetail.runID.rawValue)
                        .font(.system(.headline, design: .monospaced))
                    Spacer()
                    ProviderBadge(label: runDetail.provider)
                }

                Text("\(runDetail.status) • attempt \(runDetail.attempt)")
                    .foregroundStyle(.secondary)

                if let providerSessionID = runDetail.providerSessionID {
                    Text("Provider session: \(providerSessionID)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let lastAgentMessage = runDetail.lastAgentMessage {
                    Text(lastAgentMessage)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text("Turns: \(runDetail.turnCount) • Events: \(runDetail.logs.eventCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a run to inspect session metadata and logs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Log Viewer")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(model.liveStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.logEvents.isEmpty {
                Text("No logs loaded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.logEvents, id: \.sequence.rawValue) { event in
                    let presentation = SymphonyEventPresentation(event: event)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(presentation.title)
                                .font(.headline)
                            Spacer()
                            ProviderBadge(label: event.provider)
                        }

                        Text(presentation.detail)
                            .font(.body)

                        Text(presentation.metadata)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if presentation.showsRawJSON {
                            Text(event.rawJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

extension SymphonyOperatorRootView {
    func triggerConnect() {
        Task { await model.connect() }
    }

    func triggerRefresh() {
        Task { await model.refresh() }
    }

    func triggerIssueSelection(_ issue: IssueSummary) {
        Task { await model.selectIssue(issue) }
    }

    func triggerRunSelection(_ runID: RunID) {
        Task { await model.selectRun(runID) }
    }

    func makeIssueSelectionAction(for issue: IssueSummary) -> () -> Void {
        { triggerIssueSelection(issue) }
    }

    func makeRunSelectionAction(for runID: RunID) -> () -> Void {
        { triggerRunSelection(runID) }
    }
}

private struct ProviderBadge: View {
    let label: String

    var body: some View {
        Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

#if DEBUG
#Preview {
    SymphonyOperatorRootView(model: SymphonyOperatorModel())
}
#endif
