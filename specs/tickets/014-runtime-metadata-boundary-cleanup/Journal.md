# Journal: Runtime Metadata Boundary Cleanup

## 2026-04-05

- Created the ticket after closing 012 and reviewing the resulting runtime shape for simplification opportunities.
- Identified a concrete hop-count propagation bug in inter-agent delivery.
- Chose to capture the follow-up as a metadata-boundary cleanup rather than as another large architecture rewrite.
- Linked the work to ADR-003 so implementation can stay focused on one explicit runtime metadata projection rule.
- Validated that the ticket covers the three agreed follow-up points: hop-depth correctness, metadata-boundary cleanup, and shared programmatic delivery simplification.
- Added `Plan.md` and `Tasks.md`, then advanced the ticket to `planned`.
- Tightened the ticket to make pre-publication structure alignment explicit and to forbid retaining legacy paths or fallback behavior in the cleaned-up runtime slice.
- Refined the ticket further so the hop limit becomes configurable and hop-limit exhaustion is treated as an informative agent-visible routing outcome instead of a crash-shaped failure.