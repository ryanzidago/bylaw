# Bylaw UI MVP Implementation Plan

**Prerequisite:** PR #170 on `codex/scaffold-bylaw-ui`
**Starting point:** `codex/scaffold-bylaw-ui`
**Goal:** Deliver issue #163 as three independently reviewable stacked pull requests, ending with a publishable and acceptance-verified `bylaw-ui` package.
**Architecture:** Keep rule validation and geometry evaluation pure and browser-independent. Route browser measurement through one internal branded adapter boundary, with Playwright as the only public constructor. Publish separate root and Playwright ESM entrypoints.
**Tech Stack:** TypeScript 7, Bun 1.3.14, Playwright Core/Chromium
**Design contract:** GitHub issue #163

## Task 1: Browser-Independent Contract

**Branch:** `codex/bylaw-ui-core-contract`
**Base:** `codex/scaffold-bylaw-ui`

**Files:**

- Create: `packages/bylaw_ui/src/types.ts`
- Create: `packages/bylaw_ui/src/rules.ts`
- Create: `packages/bylaw_ui/src/internal/adapter.ts`
- Create: `packages/bylaw_ui/src/internal/validation.ts`
- Create: `packages/bylaw_ui/src/internal/geometry.ts`
- Create: `packages/bylaw_ui/src/check-layout.ts`
- Create: `packages/bylaw_ui/src/assert-layout.ts`
- Update: `packages/bylaw_ui/src/index.ts`
- Create or update: `packages/bylaw_ui/test/*.test.ts`

- [ ] Implement canonical JSON-serializable public rule helpers and exported rule/report/finding types.
- [ ] Validate helper arguments synchronously and validate every field of caller-built inline rules into structured findings.
- [ ] Evaluate alignment, ordering, overlap, containment, and size rules from finite measured rectangles.
- [ ] Implement stable report counts, diagnostics, error identity, and top-level misuse behavior.
- [ ] Cover equality, just-inside, just-outside, fractional, negative-coordinate, numeric-safety, determinism, and property invariants.
- [ ] Verify with frozen install, typecheck, build, pure tests, repository QA, `git diff --check`, and `wt step diff`.

## Task 2: Playwright Execution Boundary

**Branch:** `codex/bylaw-ui-playwright`
**Base:** `codex/bylaw-ui-core-contract`

**Files:**

- Create: `packages/bylaw_ui/src/playwright.ts`
- Create or update: `packages/bylaw_ui/test/*playwright*.test.ts`
- Update: `packages/bylaw_ui/package.json`
- Update: `packages/bylaw_ui/bun.lock`

- [ ] Add `bylaw-ui/playwright` as the only supported public adapter constructor.
- [ ] Measure all unique referenced test IDs, visibility states, rectangles, and viewport dimensions in one `page.evaluate` snapshot.
- [ ] Preserve exact test-ID, DOMRect, visibility, malformed-output, and unexpected Playwright error semantics.
- [ ] Cover transforms, scrolling, fractional coordinates, SVG, fragmented inline content, special IDs, duplicate matches, visibility boundaries, and synchronous DOM mutation.
- [ ] Verify the complete pure suite plus pinned Chromium integration tests and repeated snapshot-sensitive tests.

## Task 3: Publishable MVP and Acceptance Closure

**Branch:** `codex/bylaw-ui-mvp-release`
**Base:** `codex/bylaw-ui-playwright`

**Files:**

- Update: `packages/bylaw_ui/package.json`
- Update: `packages/bylaw_ui/tsconfig.json`
- Create: `packages/bylaw_ui/README.md`
- Create: `packages/bylaw_ui/LICENSE`
- Create or update: `packages/bylaw_ui/test/*.test.ts`
- Update: `scripts/qa.sh`

- [ ] Emit ESM JavaScript and declarations for root and Playwright entrypoints.
- [ ] Add publish metadata, explicit file allowlist, Playwright peer dependency, and prepack workflow.
- [ ] Map every issue #163 scaffold name to a meaningful assertion and reject empty, duplicate, or assertion-free coverage.
- [ ] Add realistic timeline/avatar, badge/avatar, responsive-card, and panel/control browser layouts.
- [ ] Pack and exercise the artifact from an isolated ESM TypeScript consumer.
- [ ] Add `bylaw_ui` to repository QA.

## Final Verification

- [ ] Reinstall dependencies from the frozen lockfile and regenerate build output.
- [ ] Run typechecking, build, pure tests, property tests, and actual Chromium tests.
- [ ] Run browser geometry at device scale factors 1 and 2.
- [ ] Run the browser suite ten consecutive times and verify no leaked Playwright resources.
- [ ] Audit report JSON for finite numbers and absence of browser/internal objects.
- [ ] Inspect the packed tarball allowlist and import both entrypoints from it.
- [ ] Run real passing and failing checks against the packed package.
- [ ] Run `scripts/qa.sh`, `git diff --check`, and `wt step diff`.
- [ ] Record commands and results for the final draft PR description.

## Completion Criteria

1. Each branch contains only its named behavior slice and targets the preceding branch.
2. Every issue #163 acceptance scaffold has meaningful, named coverage at the appropriate layer.
3. All focused gates and the final heavy-QA gate pass from clean generated state.
4. The packed package contains usable ESM JavaScript, declarations, README, and license without tests, browser binaries, or development-only files.
