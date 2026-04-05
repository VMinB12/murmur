# Journal: Actor Identity And Display Projection Cleanup

## 2026-04-05

- Opened this follow-up after closing ticket 014 and reviewing the post-cleanup runtime shape.
- Identified the remaining architectural seam as actor identity semantics rather than ingress metadata transport.
- Recorded ADR-004 as a proposed decision so the follow-up can be discussed explicitly before implementation.
- Drafted `Spec.md` to define the concrete actor-identity and canonical display-message requirements before planning implementation.
- Drafted `Plan.md` and `Tasks.md` to turn the approved spec into an executable implementation sequence.
- Landed the first runtime implementation slice: explicit `ActorIdentity`, `current_actor`/`origin_actor` runtime context projection, migrated `MessageInjector` and `TellAction`, and explicit actor metadata flowing through canonical ingress and visible programmatic delivery.
- Validated the slice with focused runtime, signal, and workspace LiveView tests before moving the ticket to `in-progress`.
- Landed the canonical display-message slice: added `DisplayMessage`, refactored `UITurn` to emit actor-aware display messages, normalized persisted thread entries at the projection boundary, and removed sender-name inference from content.
- Migrated shared chat rendering and workspace LiveView message creation to actor-aware labels and styling, including human task-assignment notifications that now carry explicit `origin_actor` metadata instead of UI wording in the runtime sender contract.
- Validated the display slice with focused `UITurn`, chat component, workspace LiveView, persistence, task-board, and helper regression suites.
- Ran `mix precommit` successfully after the display-model slice; tests and Credo passed cleanly, with only the existing low-confidence Sobelow warning in `apps/murmur_demo/lib/murmur_web/helpers/markdown.ex` still reported outside this ticket's touched files.
- Closed the remaining display-projection follow-up work: documented the canonical actor/display boundary in architecture docs, added helper coverage for actor-aware thread projection, and added a unified-view integration regression proving inter-agent sender labels render from actor metadata rather than content prefixes.
- Closed ticket 015 in specs after validating the full umbrella with `mix precommit`, updating the project dashboard and changelog, and accepting ADR-004 as the implemented architecture decision for the new actor/display boundary.