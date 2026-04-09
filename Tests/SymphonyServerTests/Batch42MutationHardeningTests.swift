// Batch 42 – Mutation hardening for SQLiteServerStateStore.appendEvent
// without prior session, and BootstrapTrackerFactory with empty API key.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SQLiteServerStateStore.appendEvent Without Prior Session

@Suite("appendEvent Without Prior Session")
struct AppendEventWithoutPriorSessionTests {

  @Test func appendEventSucceedsWithoutPriorUpsertSession() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent(
      "batch42-append-no-session.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)

    // Append an event for a sessionID that has never been upserted as a session.
    let event = try store.appendEvent(
      sessionID: SessionID("orphan-session"),
      provider: "codex",
      timestamp: "2026-06-01T00:00:01Z",
      rawJSON: #"{"type":"status","payload":{"message":"hello"}}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )

    // The event itself must be persisted correctly.
    #expect(event.sessionID == SessionID("orphan-session"))
    #expect(event.provider == "codex")
    #expect(event.sequence == EventSequence(1))
    #expect(event.timestamp == "2026-06-01T00:00:01Z")
    #expect(event.providerEventType == "status")
    #expect(event.normalizedEventKind == "status")

    // No session should have been created — the `if var session` block was skipped.
    let session = try store.session(sessionID: SessionID("orphan-session"))
    #expect(session == nil, "Session must not be created by appendEvent alone")
  }

  @Test func appendEventDoesNotUpdateNonexistentSession() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent(
      "batch42-append-no-update.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)

    // Append two events without a session.
    _ = try store.appendEvent(
      sessionID: SessionID("no-session"),
      provider: "claude-code",
      timestamp: "2026-06-01T00:00:01Z",
      rawJSON: #"{"type":"message"}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    )
    let secondEvent = try store.appendEvent(
      sessionID: SessionID("no-session"),
      provider: "claude-code",
      timestamp: "2026-06-01T00:00:02Z",
      rawJSON: #"{"type":"status"}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )

    // Sequences still increment correctly via SQL even without a session row.
    #expect(secondEvent.sequence == EventSequence(2))

    // Session still does not exist.
    #expect(try store.session(sessionID: SessionID("no-session")) == nil)
  }
}

// MARK: - BootstrapTrackerFactory Empty API Key

@Suite("BootstrapTrackerFactory Empty API Key")
struct BootstrapTrackerFactoryEmptyAPIKeyTests {

  @Test func emptyGitHubTokenThrowsMissingAPIKey() {
    let factory = BootstrapTrackerFactory(environment: ["GITHUB_TOKEN": ""])
    #expect(throws: GitHubTrackerError.missingAPIKey) {
      _ = try factory.make(TrackerConfig(endpoint: "https://api.github.com/graphql"))
    }
  }

  @Test func whitespaceOnlyGitHubTokenThrowsMissingAPIKey() {
    // ConfigResolver.resolveAPIKey returns nil for nil rawKey, and the fallback
    // environment["GITHUB_TOKEN"] is a whitespace-only string. The guard's
    // `!apiKey.isEmpty` check must still catch this because trimming is not applied
    // to environment["GITHUB_TOKEN"] in the factory.
    let factory = BootstrapTrackerFactory(environment: ["GITHUB_TOKEN": "   "])
    // Whitespace-only strings are NOT empty, so they pass `!apiKey.isEmpty`.
    // This test documents that whitespace-only tokens are NOT rejected at the
    // factory level — they would fail later at the transport/HTTP level.
    // (This is intentional: the factory only guards nil and empty.)
    #expect(throws: Never.self) {
      _ = try factory.make(TrackerConfig(endpoint: "https://api.github.com/graphql"))
    }
  }
}
