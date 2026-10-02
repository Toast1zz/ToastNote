import Foundation
import Testing
@testable import VaultKit

private func state(pinned: [String] = [], open: [String] = [], current: String? = nil) -> WorkspaceState {
    WorkspaceState(pinned: pinned, open: open, current: current)
}

@Suite struct WorkspaceStateTests {
    @Test func openFocusesExisting() {
        var s = state(open: ["a.md", "b.md"], current: "a.md")
        s.open("b.md")
        #expect(s.open == ["a.md", "b.md"])
        #expect(s.current == "b.md")
    }

    @Test func openFocusesAPinnedNoteWithoutDuplicatingIt() {
        var s = state(pinned: ["p.md"], open: ["a.md"], current: "a.md")
        s.open("p.md")
        #expect(s.current == "p.md")
        #expect(s.open == ["a.md"])
        #expect(s.pinned == ["p.md"])
    }

    @Test func openInsertsAfterCurrent() {
        var s = state(open: ["a.md", "b.md"], current: "a.md")
        s.open("c.md")
        #expect(s.open == ["a.md", "c.md", "b.md"])
        #expect(s.current == "c.md")
    }

    @Test func openWithPinnedCurrentInsertsAtTopOfOpen() {
        var s = state(pinned: ["p.md"], open: ["a.md"], current: "p.md")
        s.open("c.md")
        #expect(s.open == ["c.md", "a.md"])
    }

    @Test func openWithNoCurrentAppendsToEmptyList() {
        var s = state()
        s.open("a.md")
        #expect(s.open == ["a.md"])
        #expect(s.current == "a.md")
    }

    @Test func closeFocusesNextThenPrevious() {
        var s = state(open: ["a.md", "b.md", "c.md"], current: "b.md")
        s.close("b.md")
        #expect(s.open == ["a.md", "c.md"])
        #expect(s.current == "c.md")
        s.close("c.md")
        #expect(s.current == "a.md")
        s.close("a.md")
        #expect(s.current == nil)
        #expect(s.open.isEmpty)
    }

    @Test func closingTheLastOpenTabFallsBackToAPinnedNote() {
        var s = state(pinned: ["p.md"], open: ["a.md"], current: "a.md")
        s.close("a.md")
        #expect(s.current == "p.md")
    }

    @Test func closingANonCurrentTabKeepsFocus() {
        var s = state(open: ["a.md", "b.md"], current: "a.md")
        s.close("b.md")
        #expect(s.current == "a.md")
    }

    @Test func pinnedCannotClose() {
        var s = state(pinned: ["p.md"], current: "p.md")
        s.close("p.md")
        #expect(s.pinned == ["p.md"])
        #expect(s.current == "p.md")
    }

    @Test func pinRemovesFromOpen() {
        var s = state(open: ["a.md", "b.md"], current: "a.md")
        s.pin("a.md")
        #expect(s.pinned == ["a.md"])
        #expect(s.open == ["b.md"])
        #expect(s.current == "a.md")
    }

    @Test func pinningAnUnopenedNoteJustPinsIt() {
        var s = state(open: ["a.md"], current: "a.md")
        s.pin("z.md")
        #expect(s.pinned == ["z.md"])
        #expect(s.current == "a.md")
    }

    @Test func unpinGoesToTopOfOpen() {
        var s = state(pinned: ["p.md"], open: ["a.md"], current: "p.md")
        s.unpin("p.md")
        #expect(s.pinned.isEmpty)
        #expect(s.open == ["p.md", "a.md"])
        #expect(s.current == "p.md")
    }

    @Test func moveOpenReorders() {
        var s = state(open: ["a.md", "b.md", "c.md"])
        s.moveOpen(from: IndexSet(integer: 0), to: 3)
        #expect(s.open == ["b.md", "c.md", "a.md"])
        s.moveOpen(from: IndexSet(integer: 2), to: 0)
        #expect(s.open == ["a.md", "b.md", "c.md"])
    }

    @Test func orderedIsPinnedThenOpen() {
        #expect(state(pinned: ["p.md"], open: ["a.md"]).ordered == ["p.md", "a.md"])
    }

    @Test func cycleWrapsAround() {
        var s = state(pinned: ["p.md"], open: ["a.md", "b.md"], current: "b.md")
        s.selectNext()
        #expect(s.current == "p.md")
        s.selectPrevious()
        #expect(s.current == "b.md")
        s.selectPrevious()
        #expect(s.current == "a.md")
    }

    @Test func cycleWithNoCurrentSelectsTheFirst() {
        var s = state(open: ["a.md", "b.md"])
        s.selectNext()
        #expect(s.current == "a.md")
    }

    @Test func selectIndexOutOfRangeIsNoop() {
        var s = state(open: ["a.md"], current: "a.md")
        s.select(index: 5)
        s.select(index: -1)
        #expect(s.current == "a.md")
        s.select(index: 0)
        #expect(s.current == "a.md")
    }

    @Test func renameUpdatesPinnedAndOpenAndCurrent() {
        // Review Focus 4: a tab must follow a rename, never point at a missing path.
        var s = state(pinned: ["p.md"], open: ["a.md", "b.md"], current: "a.md")
        s.apply(.renamed(from: "a.md", to: "x.md"))
        s.apply(.renamed(from: "p.md", to: "q.md"))
        #expect(s.open == ["x.md", "b.md"])
        #expect(s.pinned == ["q.md"])
        #expect(s.current == "x.md")
    }

    @Test func folderRenameUpdatesPathsInside() {
        var s = state(open: ["工作/a.md", "b.md"], current: "工作/a.md")
        s.apply(.renamed(from: "工作", to: "项目"))
        #expect(s.open == ["项目/a.md", "b.md"])
        #expect(s.current == "项目/a.md")
    }

    @Test func removalDropsTabAndMovesFocus() {
        var s = state(pinned: ["p.md"], open: ["a.md", "b.md"], current: "a.md")
        s.apply(.removed("a.md"))
        #expect(s.open == ["b.md"])
        #expect(s.current == "b.md")
        s.apply(.removed("p.md"))
        #expect(s.pinned.isEmpty)
    }

    @Test func removingAFolderDropsEverythingInside() {
        var s = state(open: ["工作/a.md", "工作/b.md", "c.md"], current: "工作/a.md")
        s.apply(.removed("工作"))
        #expect(s.open == ["c.md"])
        #expect(s.current == "c.md")
    }

    @Test func createdAndModifiedChangesAreIgnored() {
        var s = state(open: ["a.md"], current: "a.md")
        s.apply(.created("b.md"))
        s.apply(.modified("a.md"))
        #expect(s.open == ["a.md"])
    }

    @Test func duplicateTitlesGetFolderSuffix() {
        let s = state(pinned: ["工作/周报.md"], open: ["生活/周报.md", "读书.md"])
        let titles = s.displayTitles()
        #expect(titles["工作/周报.md"] == "周报 — 工作")
        #expect(titles["生活/周报.md"] == "周报 — 生活")
        #expect(titles["读书.md"] == "读书")
    }
}
