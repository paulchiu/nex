import Clocks
import ComposableArchitecture
import Foundation
@testable import Nex
import Testing

/// Exercises the `pane-send-key` request/response path through the
/// reducer. Mirrors `PaneSendReplyTests` (target resolution, workspace
/// scoping, structured replies) and adds the key-name validation step
/// specific to issue #98 — unknown key names must be rejected with a
/// structured error before any surface dispatch.
@MainActor
struct PaneSendKeyReplyTests {
    private static let ws1ID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
    private static let ws2ID = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
    private static let pane1 = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
    private static let pane2 = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!

    private final class CaptureSink: @unchecked Sendable {
        var payloads: [[String: Any]] = []
        var closedCount = 0
    }

    private func makeCaptureHandle(_ sink: CaptureSink) -> SocketServer.ReplyHandle {
        SocketServer.ReplyHandle(
            id: 1,
            send: { json in sink.payloads.append(json) },
            close: { sink.closedCount += 1 }
        )
    }

    private func makeStore(
        workspaces: IdentifiedArrayOf<WorkspaceFeature.State>,
        activeWorkspaceID: UUID?
    ) -> TestStoreOf<AppReducer> {
        var appState = AppReducer.State()
        appState.workspaces = workspaces
        appState.activeWorkspaceID = activeWorkspaceID
        appState.topLevelOrder = workspaces.map { .workspace($0.id) }

        let store = TestStore(initialState: appState) {
            AppReducer()
        } withDependencies: {
            $0.surfaceManager = SurfaceManager()
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1000))
            $0.gitService.getCurrentBranch = { _ in nil }
            $0.gitService.getStatus = { _ in .clean }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func makeWorkspace(
        id: UUID,
        name: String,
        panes: [Pane]
    ) -> WorkspaceFeature.State {
        let paneIDs = panes.map(\.id)
        var layout: PaneLayout = paneIDs.isEmpty ? .empty : .leaf(paneIDs[0])
        for pid in paneIDs.dropFirst() {
            layout = layout.splitting(
                paneID: paneIDs[0], direction: .horizontal, newPaneID: pid
            ).layout
        }
        return WorkspaceFeature.State(
            id: id, name: name, slug: name.lowercased(), color: .blue,
            panes: IdentifiedArrayOf(uniqueElements: panes),
            layout: layout,
            focusedPaneID: paneIDs.first,
            createdAt: Date(timeIntervalSince1970: 1000),
            lastAccessedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    // MARK: - Success paths

    @Test func sendKeyByLabelInSameWorkspaceRepliesOk() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "enter", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads.count == 1)
        #expect(sink.closedCount == 1)
        #expect(sink.payloads[0]["ok"] as? Bool == true)
        #expect(sink.payloads[0]["pane_id"] as? String == Self.pane2.uuidString)
        #expect(sink.payloads[0]["workspace_id"] as? String == Self.ws1ID.uuidString)
        #expect(sink.payloads[0]["workspace_name"] as? String == "alpha")
        #expect(sink.payloads[0]["label"] as? String == "worker")
        #expect(sink.payloads[0]["key"] as? String == "enter")
    }

    @Test func sendKeyByUUIDRepliesOk() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2)]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: Self.pane2.uuidString, key: "tab", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == true)
        #expect(sink.payloads[0]["pane_id"] as? String == Self.pane2.uuidString)
        #expect(sink.payloads[0]["key"] as? String == "tab")
    }

    @Test func sendKeyNormalisesKeyNameToLowercase() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "ENTER", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == true)
        #expect(sink.payloads[0]["key"] as? String == "enter")
    }

    // MARK: - Key validation (issue #98)

    @Test func sendKeyRejectsUnknownKey() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "f7", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads.count == 1)
        #expect(sink.closedCount == 1)
        #expect(sink.payloads[0]["ok"] as? Bool == false)
        let error = sink.payloads[0]["error"] as? String ?? ""
        #expect(error.contains("unknown key"))
        #expect(error.contains("f7"))
        // Mentions a few of the supported names so the user knows what to try.
        #expect(error.contains("enter"))
        #expect(error.contains("tab"))
    }

    @Test func sendKeyRejectsUnknownKeyBeforeResolvingTarget() async {
        // Even when the target is bogus, the key error wins — we don't
        // want to leak target-resolution errors for invalid keys.
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1)]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "ghost", key: "bogus", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == false)
        #expect((sink.payloads[0]["error"] as? String)?.contains("unknown key") == true)
    }

    // MARK: - Workspace scoping (mirrors paneSend semantics — issue #92)

    @Test func sendKeyToLabelOnlyInOtherWorkspaceFails() async {
        let ws1 = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1)]
        )
        let ws2 = makeWorkspace(
            id: Self.ws2ID, name: "beta",
            panes: [Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws1, ws2], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "enter", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == false)
        let error = sink.payloads[0]["error"] as? String ?? ""
        #expect(error.contains("worker"))
        #expect(error.contains("--workspace"))
    }

    @Test func sendKeyWithWorkspaceResolvesCrossWorkspaceLabel() async {
        let ws1 = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1)]
        )
        let ws2 = makeWorkspace(
            id: Self.ws2ID, name: "beta",
            panes: [Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws1, ws2], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "enter", workspace: "beta"),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == true)
        #expect(sink.payloads[0]["pane_id"] as? String == Self.pane2.uuidString)
        #expect(sink.payloads[0]["workspace_id"] as? String == Self.ws2ID.uuidString)
    }

    // MARK: - Callable from outside a Nex pane (nil paneID)

    @Test func sendKeyByUUIDWithoutOriginPaneRepliesOk() async {
        // External script with no NEX_PANE_ID — UUID target should
        // resolve globally (UUIDs are unique) without needing
        // --workspace.
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2)]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: nil, target: Self.pane2.uuidString, key: "enter", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == true)
        #expect(sink.payloads[0]["pane_id"] as? String == Self.pane2.uuidString)
    }

    @Test func sendKeyByLabelWithoutOriginPaneRequiresWorkspace() async {
        // External script with no NEX_PANE_ID and no --workspace —
        // label resolution can't pick a workspace, so the request
        // must be rejected with a hint pointing at --workspace.
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: nil, target: "worker", key: "enter", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == false)
        let error = sink.payloads[0]["error"] as? String ?? ""
        #expect(error.contains("--workspace"))
    }

    @Test func sendKeyByLabelWithoutOriginPaneAndExplicitWorkspaceRepliesOk() async {
        // External script with --workspace specified — resolves
        // cleanly even without a NEX_PANE_ID origin.
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: nil, target: "worker", key: "enter", workspace: "alpha"),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == true)
        #expect(sink.payloads[0]["pane_id"] as? String == Self.pane1.uuidString)
    }

    @Test func sendKeyToUnknownTargetFails() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1)]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        let sink = CaptureSink()
        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "ghost", key: "enter", workspace: nil),
            reply: makeCaptureHandle(sink)
        ))

        #expect(sink.payloads[0]["ok"] as? Bool == false)
        #expect((sink.payloads[0]["error"] as? String)?.contains("ghost") == true)
    }

    // MARK: - Legacy fire-and-forget path

    @Test func sendKeyWithoutReplyOnSuccessStillDispatches() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "enter", workspace: nil),
            reply: nil
        ))
        // No crash; surface manager is a no-op for unregistered panes.
        #expect(store.state.workspaces[id: Self.ws1ID]?.panes[id: Self.pane2] != nil)
    }

    @Test func sendKeyWithoutReplyOnInvalidKeyIsSilentNoOp() async {
        let ws = makeWorkspace(
            id: Self.ws1ID, name: "alpha",
            panes: [Pane(id: Self.pane1), Pane(id: Self.pane2, label: "worker")]
        )
        let store = makeStore(workspaces: [ws], activeWorkspaceID: Self.ws1ID)

        await store.send(.socketMessage(
            .paneSendKey(paneID: Self.pane1, target: "worker", key: "bogus", workspace: nil),
            reply: nil
        ))
        // No crash; pane state untouched.
        #expect(store.state.workspaces[id: Self.ws1ID]?.panes[id: Self.pane2] != nil)
    }
}
