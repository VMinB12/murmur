# Journal

## 2026-04-07

- Resumed ticket 023 after confirming MDEx behavior for HTML comments versus YAML front matter.
- Narrowed the rendering scope from "all user-role messages render as markdown" to "tell-generated messages render as markdown; direct human messages stay raw text".
- Removed the previously planned direct-human comment normalization work from the ticket because it is no longer needed in this slice.
- Kept the hidden HTML comment envelope approach for tell metadata and preserved the required `intent` enum, advisory semantics, and asynchronous tell behavior.
- Implemented the tell intent enum, LLM-facing tool description, and hidden-envelope formatting in `JidoMurmur.TellAction`.
- Added `JidoMurmur.HiddenContent` as the reusable helper for Murmur's hidden HTML comment format so future trusted programmatic tools can reuse the same envelope.
- Updated the chat component to render trusted hidden-envelope programmatic messages through markdown while keeping direct human messages as raw text.
- Updated tell-focused tests, chat rendering tests, team instructions, package docs, and architecture docs.
- Ran focused tests for the changed paths and then `mix precommit`; the suite passed, with Sobelow continuing to report the existing low-confidence `XSS.Raw` finding on the markdown helper.
- Resolved the final Dialyzer issue in `JidoMurmur.TellAction` by switching `run/2` to a local schema validation path with a precise binary error contract.
- Re-ran `mix dialyzer` successfully and marked ticket 023 as done.