# Interface Describer: v1 Acceptance

The walk of [spec Section 13](app-spec.md#13-acceptance-criteria-v1) from milestone 12
([plan](plans/m12-hardening.md)). Each criterion lists the tests that prove it and the check that is still done by
hand on a Mac, since a cloud session can't drive the app. Core tests are in
`Packages/DescriberCore/Tests/DescriberCoreTests`, app tests in `InterfaceDescriberTests`; names are
`TestClass.testName`. `scripts/check.sh` runs all of them.

## Tools and canvas

| Criterion | Tests | On the Mac |
| --- | --- | --- |
| `V`, `R` and `W` switch tools, and a toast names the active tool. | Core: `KeybindTests.testSpecDefaultsResolve`, `ToolTests.testToastTexts`, `ToolTests.testToastsUseTheRegistrysKey`. App: `CanvasToolTests.testPressingRInTheCanvasPicksTheRegionToolWithAToast`, `MainMenuTests.testToolsMenuHasTheToolsSnappingAndGridSize`. | Press each key on the canvas and read the toast. |
| The Region tool draws anywhere, including inside a region, and the parenting rule assigns the parent. | Core: `CanvasGestureTests.testARegionToolDragCreatesOneSnappedRegion`, `ParentingTests.testDrawingInsideARegionMakesItTheParent`, `ParentingTests.testDrawingOverTwoNestedRegionsPicksTheInnerOne`, `ParentingTests.testEqualSizeCandidatesResolveToTheOneOnTop`. App: `CanvasToolTests.testDrawingMovingAndResizingAreOneUndoStepEach`. | Draw inside Login's sign-in form; the new region nests under it in the file. |
| Regions move and resize, snapping while snapping is on; `S` toggles it and Option inverts it. | Core: `CanvasGestureTests.testDraggingAHandleResizesWithOnlyTheDraggedEdgesSnapped`, `CanvasGestureTests.testOptionInvertsSnappingForTheGesture`, `SnappingTests.*`. App: `CanvasToolTests.testSnappingTogglesWithAToastAndHidesTheGrid`. | Drag with and without Option held, snapping on and off. |
| `G` opens a grid-size slider with fixed steps; changing it never moves or resizes regions. | Core: `SnappingTests.testGridStepsAndNudgeDistances`, `SnappingTests.testChangingOnlyTheGridSizeChangesNoFrame`. App: `CanvasToolTests.testChangingTheGridSizeMovesNoRegionAndIsSaved`. | Press `G` and slide through 4 to 32 pt. |
| Moving a parent moves its children; dragging into or out of a region re-parents it. | Core: `CommandTests.testMovingAParentMovesEveryDescendantByTheSameDelta`, `ParentingTests.testDraggingIntoAndOutOfARegionReparents`, `CommandTests.testResizingAParentSoAChildNoLongerFitsReparentsItAndUndoPutsItBack`. App: `UndoAuditTests` ("Drag a region into another"). | Drag the logo into the sign-in form and out again. |
| Marquee and Shift-click build a multi-selection; move and delete work on it; `Shift-Return` selects the parent. | Core: `CanvasGestureTests.testDraggingOnEmptyCanvasSelectsEveryRegionTheMarqueeTouches`, `CanvasGestureTests.testShiftClickTogglesARegion`, `CanvasGestureTests.testDraggingARegionMovesTheWholeSelectionInOneCommand`, `SelectionEditingTests.testSelectParentReachesAParentCoveredByItsChildren`. App: `CanvasToolTests.testAMarqueeSelectsTheRegionsItTouches`, `SelectionEditingTests.testSelectAllThenDeleteRemovesEveryRegionInOneStep`, `SelectionEditingTests.testSelectParentAndChildrenWalkTheTree`. | Marquee three fields, drag them, delete them, undo. |
| Regions smaller than 4 × 4 pt can't be created. | Core: `CommandTests.testCreateOrResizeBelowMinimumSizeIsRejectedAndChangesNothing`, `CanvasGestureTests.testADragUnderTheMinimumSizeCreatesNothing`, `CanvasGestureTests.testAHandleStopsAtTheMinimumSize`. | A tiny drag with the Region tool draws nothing. |

## Details panel

| Criterion | Tests | On the Mac |
| --- | --- | --- |
| Drawing opens the panel with the title focused and the canvas zoomed to fit the region on the left. | App: `DetailsPanelTests.testDrawingOpensThePanelWithTheTitleFocusedAndFitsTheRegion`. | Watch the panel slide in and the canvas zoom. |
| Return moves from title to description; Escape commits and closes, restoring zoom and pan. | App: `DetailsPanelTests.testReturnAndTabMoveBetweenFields`, `DetailsPanelTests.testATitledNewRegionIsOneUndoStep`. | Type, press Return, type, press Escape; the camera returns. |
| A new region with a blank title is discarded on close. | Core: `RegionEditorTests.testANewRegionWithABlankTitleIsDiscarded`. App: `UndoAuditTests` ("Draw a region and leave its title blank"). | Draw, press Escape at once. |
| Kind, links and scrolling can be set in the panel. | App: `DetailsPanelTests.testKindLinksAndScrollingAreOneEditRegionStep`, `UndoAuditTests` ("Edit every field in the panel"). | Set each and reopen the region. |

## Screens and links

| Criterion | Tests | On the Mac |
| --- | --- | --- |
| Screens can be created, renamed, reordered, duplicated, deleted, and given a kind and viewport, including This Device, Custom and user presets. | Core: `CommandTests.testEveryScreenCommandUndoesAndRedoesToTheSameBytes`, `ViewportPresetTests.*`. App: `ScreenManagementTests.testEachScreenActionIsOneNamedStep`, `ScreenManagementTests.testThisDeviceUsesTheMeasuredDisplayAndRefreshMeasuresAgain`, `ScreenManagementTests.testASavedPresetReachesTheSettingsFileAndTheViewportMenu`. | Do each from the sidebar's context menu and the Screen menu. |
| Screens can be grouped as variants. | Core: `CommandTests.testNewVariantJoinsOrCreatesTheGroup`. App: `ScreenManagementTests.testJoiningAScreenWithoutAGroupMakesOneNamedAfterTheTarget`, `ScreenManagementTests.testTheSidebarShowsAHeaderAboveEachGroup`. | New Variant of Settings at iPad; the sidebar shows them together. |
| Links are followed with Cmd-click or `L`; Back and Forward return through the history. | App: `ScreenManagementTests.testCommandClickAndLFollowLinksAndBackAndForwardReturn`, `ScreenManagementTests.testAChooserPicksAmongSeveralLinks`, `ScreenManagementTests.testHistoryGoesBackAndForwardLikeABrowser`. | Cmd-click Forgot password, then Cmd-Option-← and →. |
| A scrollable region can be scrolled in the editor to place children in its hidden content. | App: `ScrollingTests.testScrollingOverASelectedScrollableRegionScrollsItAndNotTheCamera`, `ScrollingTests.testDrawingAfterScrollingPlacesAChildInTheHiddenContent`. Core: `ScrollingTests.testDrawingInScrolledContentMakesAChildThere`. | Select Settings' list, scroll it with two fingers, draw below the fold. |

## Persistence and export

| Criterion | Tests | On the Mac |
| --- | --- | --- |
| A project saves as a `.uidesc` package with one JSON file per screen, reopens with identical content, and autosaves. | Core: `ExampleProjectTests.testExampleProjectResavesByteForByte`, `ProjectPackageTests.*`. App: `DocumentTests.testExampleReadsAndWritesBackByteForByte`, `DocumentTypeTests.testProjectTypeIsAPackageWithTheExpectedExtension`. | Edit, wait, quit without saving, reopen: the edit is there. |
| Saved JSON uses the fixed key order and omits empty optional fields. | Core: `ProjectEncodingTests.*`, `ExampleProjectTests.testExampleProjectMatchesTheSchema`. | None. |
| A package with a different `schemaVersion` shows an error and opens nothing. | Core: `ProjectDecodingTests.testUnsupportedSchemaVersionIsCheckedBeforeAnyScreenFileIsRead`. App: `DocumentTests.testUnsupportedSchemaVersionFailsToRead`. | Edit `schemaVersion` to 2 and open it. |
| PNG, Markdown and single-file JSON exports match the project's content. | Core: `ExampleProjectTests.testExampleExportsAreWhatTheExportersWrite`, `ExportTests.*`. App: `ExportTests.*`. | Export all three from the example and read them. |
| App settings, including user presets, persist across relaunch. | Core: `SettingsTests.testAFileWithEveryKeyReadsEveryValue`, `SettingsTests.testSavingAPresetKeepsTheOtherSettings`. App: `ScreenManagementTests.testASavedPresetReachesTheSettingsFileAndTheViewportMenu`. | Save a preset, relaunch, find it in the Viewport menu. |
| Hand edits to `settings.json` apply without relaunching; an invalid file shows an error and leaves the settings and the file untouched. | App: `SettingsTests.testTheWatcherAppliesAnAtomicReplace`, `SettingsTests.testTheWatcherAppliesAWriteInPlace`, `SettingsTests.testABadFileShowsTheBannerAndKeepsTheKeysUntilItIsFixed`. Core: `SettingsTests.testEachBadValueIsAnErrorNamingItsKey`. | Rebind `R` in the file and save; then break the JSON. |

## Quality

| Criterion | Tests | On the Mac |
| --- | --- | --- |
| Undo and redo work for every canvas, panel and screen change; one drag and one panel session on a field are one step each. | Core: `CommandTests.testEveryCommandTypeHasAnUndoTest` and the two round-trip tests, `RegionEditorTests.testSeveralChangedFieldsAreOneEditRegionStep`. App: `UndoAuditTests.testEveryEditIsOneUndoStepThatUndoesAndRedoesToTheSameBytes`, `UndoAuditTests.testEditorOnlyActionsAddNoStepAndChangeNoContent`, `DetailsPanelTests.testUndoWhileThePanelIsOpenRevertsTheSessionAndClosesIt`. | Make a dozen mixed edits, undo them all, redo them all. |
| No canvas or tool keybind fires while a text field is being edited. | Core: `KeybindTests.testOnlyStandardEditingShortcutsResolveWhileEditingText`. App: `KeybindAuditTests.*`, `SelectionEditingTests.testCanvasKeysAreOffWhileTheTitleIsEditedAndOnWithTheCanvasFocused`. | Type `rvsdl` and press arrows, Cmd + and Ctrl-Cmd-S in a title; only text changes. |
| Pan, zoom and drag stay smooth with 500 regions on a screen. | App: `CanvasPerformanceTests.testStressProjectUpdatesWithinBudget`, `CanvasPerformanceTests.testGesturesOnTheStressProjectStayWithinBudget`. | Debug > New 500-Region Document: pan, pinch, Cmd-A and drag. |

## Known gaps

- Zoom, pan, grid size, scroll positions and shown descriptions are saved with the next save an edit triggers, not on
  their own (milestone 4's decision). Closing a window after only panning keeps the old camera.
- Typing undo inside the sidebar's rename and size fields has no test; only the details panel's fields do
  (milestone 6). The Mac check for undo covers it.
