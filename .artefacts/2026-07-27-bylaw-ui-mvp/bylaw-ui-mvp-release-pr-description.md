<!--
Replace the three branch placeholders below with full PR URLs after the stack is
opened. No PRs existed for these branches when this description was prepared.
-->
<!-- stack:bylaw-ui-mvp:start -->
## 🥞 Stack: `bylaw-ui-mvp`

- `codex/bylaw-ui-core-contract` — Add the browser-independent Bylaw UI contract
  - `codex/bylaw-ui-playwright` — Add the Playwright layout measurement boundary
    - 👉 **`codex/bylaw-ui-mvp-release` — Publish the Bylaw UI MVP** ← _you are here_
<!-- stack:bylaw-ui-mvp:end -->

---

## Goal

Frontend teams need deterministic, structured layout checks without coupling rule evaluation to a browser runtime. This stack delivers the initial `bylaw-ui` package: pure geometry contracts, a single-snapshot Playwright measurement boundary, and a publishable package validated against the complete acceptance contract in [#163](https://github.com/ryanzidago/bylaw/issues/163).

## What

Stacks on `codex/bylaw-ui-playwright`; replace this branch reference with the full parent PR URL after the stack is opened.

This PR turns the completed core and Playwright layers into a publishable `bylaw-ui` 0.1.0 package. It emits ESM JavaScript and declarations for the root and `bylaw-ui/playwright` entrypoints, adds package metadata and documentation, incorporates the package into repository QA, and closes every remaining acceptance scaffold with meaningful coverage.

The package is also packed and installed into an isolated NodeNext TypeScript consumer, where both entrypoints are imported and real passing and failing Chromium layout checks are exercised.

## Why

Consumers need confidence that the package boundary behaves like the source tree: declarations resolve, the optional Playwright entrypoint composes with the root evaluator, browser measurements retain CSS-pixel semantics, and published artifacts exclude development-only files. The release gate catches packaging, module-identity, browser-lifecycle, and acceptance-coverage failures before publication.

Previous steps: the browser-independent contract and Playwright execution boundary are the first two PRs in this stack.

Next steps: cross-browser certification may be added after Chromium-backed V1 usage establishes the required compatibility surface.

### API changes

**Before**

```text
No published package API.
```

**After**

```ts
import {
  LayoutAssertionError,
  assertLayout,
  checkLayout,
  rules,
} from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
```

### Example

```ts
const report = await checkLayout(
  playwright(page),
  rules.containedBy("status-badge", "avatar"),
);

if (!report.ok) {
  console.error(report.findings);
}
```

## Validation

- `bun install --frozen-lockfile --force` — passed from freshly generated dependencies.
- `bun run check` — 500 tests passed across 20 files with 7,441 assertions.
- `bun run test:package` — packed tarball installed and typechecked in an isolated ESM NodeNext consumer; both entrypoints imported; real passing and failing Chromium checks passed.
- `bun test test/browser` repeated 10 times — 53 tests and 130 assertions passed identically on every run.
- Device scale factors 1 and 2 — both passed with CSS-pixel geometry.
- Browser lifecycle audit — no leaked pages, contexts, or Chromium processes.
- Acceptance scaffold audit — all 488 unique names from #163 matched exactly once; no missing, duplicate, empty, or assertion-free tests.
- Report audit — JSON serialization passed with finite values and no DOM, Playwright, adapter, or internal fields.
- Packed artifact audit — JavaScript, declarations, README, and license present; source tests, browser binaries, dependencies, lockfiles, and development configuration absent.
- `scripts/qa.sh` — passed for the complete repository.
- `git diff --check` — passed.
- `wt step diff codex/bylaw-ui-playwright` — reviewed as the release-layer diff.

## Out of scope

- Cross-browser certification beyond the pinned Chromium build.
- Screenshot-based acceptance criteria.
