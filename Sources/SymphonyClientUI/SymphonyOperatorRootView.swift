import SwiftUI
import SymphonyShared

public struct SymphonyOperatorRootView: View {
    @ObservedObject var model: SymphonyOperatorModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(model: SymphonyOperatorModel) {
        self.model = model
    }

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    public var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
                    connectionCard
                    issuesSection
                }
                .padding(isCompact ? 12 : 20)
            }
            .navigationTitle("Symphony")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
                    issueDetailSection
                    runDetailSection
                    logsSection
                }
                .padding(isCompact ? 12 : 20)
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
                    .accessibilityIdentifier("connection-host")
                TextField("Port", text: $model.portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .accessibilityIdentifier("connection-port")
            }

            HStack {
                Button(model.isConnecting ? "Connecting…" : "Connect", action: triggerConnect)
                .disabled(model.isConnecting)
                .accessibilityIdentifier("connect-button")

                Button(model.isRefreshing ? "Refreshing…" : "Refresh", action: triggerRefresh)
                .disabled(model.isRefreshing || model.isConnecting)
                .accessibilityIdentifier("refresh-button")
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
        .accessibilityIdentifier("connection-card")
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Issues")
                .font(.title3.weight(.semibold))

            if model.issues.isEmpty {
                Text("No issues loaded.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("issues-empty")
            } else {
                ForEach(model.issues, id: \.issueID.rawValue) { issue in
                    Button(action: makeIssueSelectionAction(for: issue)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(issue.identifier.rawValue)
                                    .font(.headline)
                                if let priority = issue.priority {
                                    Text("P\(priority)")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                }
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
                    .accessibilityIdentifier("issue-row-\(issue.issueID.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("issues-section")
    }

    private var issueDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Issue Detail")
                .font(.title3.weight(.semibold))

            if let detail = model.issueDetail {
                Text(detail.issue.title)
                    .font(.title2.weight(.semibold))

                HStack {
                    Text(detail.issue.identifier.rawValue)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let urlString = detail.issue.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.callout)
                        }
                        .accessibilityIdentifier("issue-url-link")
                    }
                }

                if let description = detail.issue.description {
                    Text(description)
                }

                if !detail.issue.labels.isEmpty {
                    issueLabels(detail.issue.labels)
                }

                if let createdAt = detail.issue.createdAt {
                    Text("Created: \(createdAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updatedAt = detail.issue.updatedAt {
                    Text("Updated: \(updatedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !detail.issue.blockedBy.isEmpty {
                    blockersList(detail.issue.blockedBy)
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
                    .accessibilityIdentifier("latest-run-button")
                }

                if !detail.recentSessions.isEmpty {
                    recentSessionsList(detail.recentSessions)
                }
            } else {
                Text("Select an issue to inspect its workspace, runs, and sessions.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("issue-detail-section")
    }

    private func issueLabels(_ labels: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func blockersList(_ blockers: [BlockerReference]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Blocked By")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(blockers, id: \.issueID.rawValue) { blocker in
                HStack {
                    Text(blocker.identifier.rawValue)
                        .font(.system(.caption, design: .monospaced))
                    Text("(\(blocker.state))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recentSessionsList(_ sessions: [AgentSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sessions, id: \.sessionID.rawValue) { session in
                HStack {
                    ProviderBadge(label: session.provider)
                    Text(session.status)
                        .font(.caption)
                    Spacer()
                    Text("Turns: \(session.turnCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastEventAt = session.lastEventAt {
                        Text(lastEventAt)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .accessibilityIdentifier("recent-sessions")
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

                tokenUsageView(runDetail.tokens)

                if let lastAgentEventType = runDetail.lastAgentEventType {
                    Text("Last event: \(lastAgentEventType)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("run-last-event-type")
                }

                if let lastAgentMessage = runDetail.lastAgentMessage {
                    Text(lastAgentMessage)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("run-last-message")
                }

                if let lastError = runDetail.lastError {
                    Text(lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("run-last-error")
                }

                Text("Turns: \(runDetail.turnCount) • Events: \(runDetail.logs.eventCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let endedAt = runDetail.endedAt {
                    Text("Ended: \(endedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("run-ended-at")
                }
            } else {
                Text("Select a run to inspect session metadata and logs.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("run-detail-section")
    }

    private func tokenUsageView(_ tokens: TokenUsage) -> some View {
        HStack(spacing: 12) {
            if let input = tokens.inputTokens {
                tokenPill(label: "In", value: input)
            }
            if let output = tokens.outputTokens {
                tokenPill(label: "Out", value: output)
            }
            if let total = tokens.totalTokens {
                tokenPill(label: "Total", value: total)
            }
        }
        .accessibilityIdentifier("token-usage")
    }

    private func tokenPill(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .accessibilityIdentifier("live-status")
            }

            if model.logEvents.isEmpty {
                Text("No logs loaded.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("logs-empty")
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
                    .background(eventBackground(for: event.normalizedKind), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("log-event-\(event.sequence.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("logs-section")
    }

    private func eventBackground(for kind: NormalizedEventKind) -> Color {
        switch kind {
        case .error:
            return Color.red.opacity(0.08)
        case .approvalRequest:
            return Color.orange.opacity(0.08)
        default:
            return Color.secondary.opacity(0.08)
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
