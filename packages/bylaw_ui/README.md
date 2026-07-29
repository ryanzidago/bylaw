# bylaw-ui

`bylaw-ui` is a browser-independent UI contract evaluator for coding agents. It
captures a small number of representative rendered states and produces
compiler-like, machine-readable diagnostics from many declarative contracts.

The intended usage model is **few rendered states, many contracts**:

1. Playwright or another adapter renders a representative UI state.
2. Bylaw captures one measurement snapshot for that state.
3. Many pure contracts evaluate the snapshot.
4. The coding agent receives one structured report containing all findings.

The current release evaluates objective geometry contracts. Style, typography,
and asset contracts belong to the target product model described below, but
those rule families are not released APIs yet.

## Install

`bylaw-ui` is not published to npm yet. To try it from a Bylaw checkout, build
the package and install that local directory into the application you want to
check:

```sh
git clone https://github.com/ryanzidago/bylaw.git
cd bylaw/packages/bylaw_ui
bun install --frozen-lockfile
bun run build

cd /path/to/your-application
bun add --dev /path/to/bylaw/packages/bylaw_ui @playwright/test
```

Building before the local install ensures the application receives the compiled
entrypoints. The package also runs its QA suite when it is packed for
publication. When it is published, the application install becomes
`bun add --dev bylaw-ui @playwright/test`.

Chromium is the verified V1 browser target. Install the browser build matching
the application's Playwright version:

```sh
bunx playwright install chromium
```

## Current API

The package has two entrypoints:

- `bylaw-ui` exports the browser-independent rules, evaluator, report assertion,
  public adapter factory, error classes, and their TypeScript types.
- `bylaw-ui/playwright` exports `playwright`, `waitForLayoutTargets`,
  `LayoutReadinessTimeoutError`, and their TypeScript types.

Rules use logical target names. Binary rules take `subject, reference` in that
order:

| Contract                          | Helper                                 | Options                        |
| --------------------------------- | -------------------------------------- | ------------------------------ |
| Align edges or centers            | `align(subject, reference, alignment)` | `tolerancePx`                  |
| Place one target above another    | `above(subject, reference)`            | `tolerancePx`, `gap`           |
| Place one target below another    | `below(subject, reference)`            | `tolerancePx`, `gap`           |
| Place one target left of another  | `leftOf(subject, reference)`           | `tolerancePx`, `gap`           |
| Place one target right of another | `rightOf(subject, reference)`          | `tolerancePx`, `gap`           |
| Require overlap                   | `overlap(subject, reference)`          | horizontal and vertical ranges |
| Prohibit overlap                  | `notOverlap(subject, reference)`       | none                           |
| Contain one target inside another | `inside(subject, reference)`           | `tolerancePx`                  |
| Match width                       | `sameWidth(subject, reference)`        | `tolerancePx`                  |
| Match height                      | `sameHeight(subject, reference)`       | `tolerancePx`                  |
| Match width and height            | `sameSize(subject, reference)`         | `tolerancePx`                  |
| Constrain one target's width      | `width(target, range)`                 | inclusive pixel range          |
| Constrain one target's height     | `height(target, range)`                | inclusive pixel range          |
| Keep one target in the viewport   | `inViewport(target)`                   | none                           |

An alignment is `left`, `right`, `top`, `bottom`, `centerX`, or `centerY`.
Pixel ranges use an inclusive `minPx`, `maxPx`, or both. Rule helpers validate
their inputs immediately; structurally valid `LayoutRule` objects can also be
serialized and supplied directly to `checkLayout`.

## Use one snapshot for many contracts

Import rules and reporting from the package root. Import the browser integration
from the separate Playwright entrypoint.

```ts
import {
  align,
  assertLayout,
  checkLayout,
  height,
  inViewport,
  inside,
  leftOf,
  notOverlap,
  sameHeight,
  width,
} from "bylaw-ui";
import { playwright, waitForLayoutTargets } from "bylaw-ui/playwright";

// Playwright owns browser and application-state orchestration.
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto("/pull/55/files");
await page.getByRole("button", { name: "Split" }).click();

const changedFiles = page.getByRole("region", { name: "Changed files" });
const adapter = playwright(page, {
  targets: {
    sidebar: page.getByRole("navigation", { name: "File tree" }),
    toolbar: page.getByRole("toolbar"),
    "toolbar-title": page.getByRole("heading", { name: "Files changed" }),
    "toolbar-actions": page.getByRole("group", { name: "File actions" }),
    "file-content": changedFiles,
    "package-json-card": changedFiles.getByRole("article", {
      name: /package\.json/,
    }),
    "package-json-viewed": changedFiles.getByRole("checkbox", {
      name: "Viewed",
    }),
  },
});

const rules = [
  // Absolute geometry.
  width("sidebar", { minPx: 260, maxPx: 280 }),
  height("toolbar", { minPx: 48 }),
  inViewport("file-content"),

  // Relationships within the same rendered state.
  leftOf("sidebar", "file-content", {
    gap: { minPx: 8, maxPx: 24 },
  }),
  align("toolbar-title", "toolbar-actions", "centerY", {
    tolerancePx: 1,
  }),
  inside("package-json-viewed", "package-json-card"),
  sameHeight("toolbar-title", "toolbar-actions", { tolerancePx: 2 }),
  notOverlap("sidebar", "toolbar-actions"),
];

// Readiness is explicit and opt-in.
await waitForLayoutTargets(adapter, rules, {
  timeoutMs: 1_000,
  stableFrames: 2,
});

// checkLayout takes one immediate browser-side snapshot for every referenced
// target, evaluates every independent rule, and returns all findings together.
const report = await checkLayout({ adapter, rules });
assertLayout(report);
```

This example renders the desktop split state once. It does not reload or
rediscover that state for each rule. `checkLayout` asks the adapter to measure
all referenced targets together, then evaluates the rules against that one
snapshot. A failed rule does not prevent independent rules from running.

The JSON-serializable report is suitable for direct coding-agent feedback:

```ts
{
  passed: false,
  rules: { total: 8, passed: 6, failed: 2, skipped: 0 },
  findings: [
    {
      category: "layout",
      code: "dimension-out-of-range",
      ruleIndex: 0,
      target: "sidebar",
      relationship: "width",
      expected: { range: { minPx: 260, maxPx: 280 } },
      actual: { widthPx: 288 },
      message: "..."
    },
    {
      category: "layout",
      code: "alignment-mismatch",
      ruleIndex: 4,
      subject: "toolbar-title",
      reference: "toolbar-actions",
      relationship: "align",
      expected: { alignment: "centerY", tolerancePx: 1 },
      actual: {
        subjectCoordinate: 24,
        referenceCoordinate: 28,
        differencePx: 4
      },
      message: "..."
    }
  ]
}
```

Use `assertLayout` when the surrounding test runner should fail. Its
`LayoutAssertionError` includes actionable geometry diagnostics and retains the
original structured report for programmatic consumers.

## Put contracts into an agent repair loop

Keep state setup, logical targets, and contracts close enough that a coding
agent can discover and change them together. One practical organization is:

```text
tests/ui/
  contracts/
    pull-request-layout.ts
  pull-request-layout.spec.ts
```

The contract module exports targets and rules for each representative state:

```ts
// tests/ui/contracts/pull-request-layout.ts
import type { Page } from "@playwright/test";
import { align, height, inside, leftOf, width } from "bylaw-ui";

export const desktopSplitRules = [
  width("sidebar", { minPx: 260, maxPx: 280 }),
  height("toolbar", { minPx: 48 }),
  leftOf("sidebar", "file-content", {
    gap: { minPx: 8, maxPx: 24 },
  }),
  align("toolbar-title", "toolbar-actions", "centerY", {
    tolerancePx: 1,
  }),
  inside("viewed-control", "changed-file"),
];

export function desktopSplitTargets(page: Page) {
  const changedFiles = page.getByRole("region", { name: "Changed files" });

  return {
    sidebar: page.getByRole("navigation", { name: "File tree" }),
    toolbar: page.getByRole("toolbar"),
    "toolbar-title": page.getByRole("heading", { name: "Files changed" }),
    "toolbar-actions": page.getByRole("group", { name: "File actions" }),
    "file-content": changedFiles,
    "changed-file": changedFiles.getByRole("article", {
      name: /package\.json/,
    }),
    "viewed-control": changedFiles.getByRole("checkbox", {
      name: "Viewed",
    }),
  };
}
```

The Playwright spec owns navigation and state setup, then evaluates all rules for
that state in one snapshot:

```ts
// tests/ui/pull-request-layout.spec.ts
import { test } from "@playwright/test";
import { assertLayout, checkLayout } from "bylaw-ui";
import { playwright, waitForLayoutTargets } from "bylaw-ui/playwright";
import {
  desktopSplitRules,
  desktopSplitTargets,
} from "./contracts/pull-request-layout.js";

test("desktop split view satisfies its UI contracts", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/pull/55/files");
  await page.getByRole("button", { name: "Split" }).click();

  const rules = desktopSplitRules;
  const adapter = playwright(page, {
    targets: desktopSplitTargets(page),
  });

  await waitForLayoutTargets(adapter, rules, {
    timeoutMs: 1_000,
    stableFrames: 2,
  });

  assertLayout(await checkLayout({ adapter, rules }));
});
```

Run the state directly while iterating:

```sh
bunx playwright test tests/ui/pull-request-layout.spec.ts
```

When an agent receives a failing report:

1. Confirm that the test reached the intended viewport and application state.
2. Resolve missing, duplicate, hidden, or unstable targets before interpreting
   geometry findings.
3. Use each finding's target names, measured geometry, and expected constraint
   to locate the product code responsible for the mismatch.
4. Fix the product UI when the stated contract is still correct. Change a
   contract only when the product requirement changed.
5. Run the focused state again, then run the application's normal UI test suite.

Do not widen tolerances, replace semantic locators with brittle selectors, or
change production markup merely to clear a report. A stable `data-testid` can be
an intentional product testing boundary, but registered role, label, and scoped
locators are preferred when they express the target clearly. Keep screenshot
review for subjective qualities that geometry contracts cannot represent.

### Optional repository instructions

You do not need an `AGENTS.md` to use `bylaw-ui`. Add guidance to an existing
repository instruction file only when coding agents are expected to maintain
the UI contracts. For example:

```md
For objective UI geometry requirements, use `bylaw-ui`.

Group contracts by representative rendered state. Use semantic Playwright
locators, call `waitForLayoutTargets` before `checkLayout`, and evaluate all
contracts for one state from a single snapshot.

Treat missing, duplicate, hidden, and unstable targets as state or locator
problems first. Do not weaken tolerances or alter locators merely to clear a
failure. Use screenshots separately for subjective visual assessment.
```

Place these instructions in the consumer repository's existing `AGENTS.md` or
equivalent file. The Bylaw package does not ship its own agent instruction file:
package documentation explains the reusable API, while each consumer owns its
state setup, test commands, product requirements, and agent workflow.

## Reports and errors

`checkLayout` always returns a `Promise<LayoutReport>`. It collects independent
findings in supplied rule order and does not throw for an invalid rule, an
unresolved or unavailable target, or a violated geometry contract:

- Invalid rules and geometry violations count as `failed`.
- Rules whose targets are missing, duplicated, hidden, or zero-size count as
  `skipped` and include element-resolution or element-visibility findings.
- A report passes only when every rule passes and `findings` is empty.

`assertLayout(report)` returns normally for a passing report. For a failing
report it throws `LayoutAssertionError`, whose message includes the relevant
measured geometry and allowed constraint and whose `report` property is the
original report.

Boundary and platform failures remain exceptions. Invalid call shapes throw
`TypeError`; malformed custom-adapter snapshots throw
`MeasurementValidationError` before evaluation; browser or adapter errors
propagate unchanged.

## Group contracts by rendered state

A UI normally needs a few representative states rather than one test per
contract. Keep browser setup at the state boundary and pass all contracts for
that state to one `checkLayout` call:

```ts
const stateContracts = {
  "desktop-unified": desktopUnifiedRules,
  "desktop-split": desktopSplitRules,
  mobile: mobileRules,
  loading: loadingRules,
  error: errorRules,
};

for (const [state, rules] of Object.entries(stateContracts)) {
  test(`${state} satisfies its UI contracts`, async ({ page }) => {
    await renderState(page, state);

    const adapter = playwright(page, {
      targets: targetsFor(page, state),
    });

    await waitForLayoutTargets(adapter, rules, {
      timeoutMs: 1_000,
      stableFrames: 2,
    });

    assertLayout(await checkLayout({ adapter, rules }));
  });
}
```

Choose states that materially change what is rendered or which contracts
apply. Desktop unified, desktop split, mobile, loading, and error are examples,
not a required state taxonomy.

## Resolve targets

Pass logical names to rules and register their Playwright locators on the
adapter. Locators can use roles, labels, text, test IDs, filtering, frame
locators, and normal Playwright composition. Registered locators are resolved
from the current page state without Playwright auto-waiting.

Every target used by a current geometry rule is singular. Exactly one match is
required. Zero and multiple matches become explicit report findings; Bylaw
never selects the first match. A registered locator takes precedence over
fallback lookup even when it resolves to zero or multiple elements.

An unregistered logical name falls back to an exact, case-sensitive
`data-testid` value. Whitespace and special characters are preserved. Prefer a
registered semantic locator when the rule should not depend on production test
markup.

## Wait for layout readiness

`waitForLayoutTargets` accepts only an adapter returned by `playwright`. It is
not available for public custom adapters, whose consumers own platform-specific
waiting.

```ts
import {
  LayoutReadinessTimeoutError,
  playwright,
  waitForLayoutTargets,
} from "bylaw-ui/playwright";

const adapter = playwright(page, { targets });

try {
  await waitForLayoutTargets(adapter, rules, {
    timeoutMs: 1_000,
    stableFrames: 2,
  });
} catch (error) {
  if (error instanceof LayoutReadinessTimeoutError) {
    console.error({
      unresolved: error.unresolvedTargets,
      unstable: error.unstableTargets,
      lastObserved: error.lastObserved,
    });
  }

  throw error;
}
```

`timeoutMs` must be a positive finite number and `stableFrames` must be a
positive integer. Stability tracks only the normalized geometry required by
the supplied rules, plus viewport dimensions for `inViewport`. A timeout
identifies unresolved and unstable targets and preserves their last observed
match count and geometry. Readiness does not assert rule compliance,
visibility, or positive size.

## Ownership boundaries

### Browser and state orchestration

Playwright or another consumer-owned adapter navigates, authenticates, chooses
the viewport, loads fixtures, operates controls, and reaches the intended UI
state. It also owns any application-specific waiting. The optional Playwright
`waitForLayoutTargets` helper can then wait for referenced targets to resolve
and stabilize.

### Measurement and contract evaluation

Bylaw measures the targets referenced by the supplied rules and evaluates
explicit contracts over normalized measurements. `checkLayout` is immediate
and deterministic: it does not navigate, mutate the DOM, infer design intent,
auto-wait, or retry. The package root remains browser-independent, so Playwright,
CDP, WebDriver, MCP, or static-layout sources can feed the same pure evaluator
through an adapter.

Layout readiness and assertion evaluation are separate, explicit operations.
`waitForLayoutTargets` waits only for referenced targets to resolve and for the
normalized geometry used by their rules to remain unchanged for the requested
number of consecutive animation frames. It does not require targets to be
visible, non-zero-size, or compliant with the rules. The subsequent
`checkLayout` call takes one immediate snapshot and evaluates the assertions.

### Screenshot evidence

Screenshots remain useful supplemental evidence for emergent visual character:
hierarchy, balance, composition, and resemblance to a reference. Use objective
contracts for facts such as dimensions, alignment, containment, and spacing;
use screenshots for qualities that are not faithfully reducible to those
contracts. A screenshot is not the measurement input to the current geometry
engine.

## Avoid per-rule browser tests

Do not create one page load or Playwright test per individual contract:

```ts
// Avoid: the same state is rendered and measured once per rule.
test("sidebar width", async ({ page }) => {
  await renderDesktopSplit(page);
  assertLayout(
    await checkLayout({
      adapter: playwright(page),
      rules: [width("sidebar", { minPx: 260, maxPx: 280 })],
    }),
  );
});

test("toolbar height", async ({ page }) => {
  await renderDesktopSplit(page);
  assertLayout(
    await checkLayout({
      adapter: playwright(page),
      rules: [height("toolbar", { minPx: 48 })],
    }),
  );
});
```

This repeats expensive state setup, fragments findings across test failures,
and makes Bylaw behave like a thin assertion helper inside ordinary browser
tests. Group both rules with the other desktop split contracts and evaluate
them from one snapshot instead.

Do not dispatch selectors from test titles:

```ts
// Avoid: renaming a test can change which element gets measured.
const selector = selectorByTestTitle[testInfo.title];
```

Test titles are human documentation, not target identifiers. Give rules stable
logical target names and map those names directly to locators.

Do not mutate the runtime DOM to create a consumer-specific selector namespace:

```ts
// Avoid: the test changes the page it intends to measure.
await page.locator(".file-card").evaluateAll((cards) => {
  cards.forEach((card, index) => {
    card.setAttribute("data-testid", `bylaw-file-card-${index}`);
  });
});
```

Register semantic Playwright locators instead. Locator composition can scope a
descendant to its container without changing production markup:

```ts
const changedFiles = page.getByRole("region", { name: "Changed files" });

const report = await checkLayout({
  adapter: playwright(page, {
    targets: {
      "changed-file": changedFiles.getByRole("row", {
        name: /package\.json/,
      }),
      "viewed-control": changedFiles.getByRole("checkbox", {
        name: "Viewed",
      }),
    },
  }),
  rules: [inside("viewed-control", "changed-file")],
});
```

Only registered targets referenced by the supplied rules are resolved. A
registered locator takes precedence over `data-testid` fallback, including
when it has zero or multiple matches. Unregistered names continue to resolve
against exact, case-sensitive `data-testid` values.

## Target product model

The intended evaluator spans geometry, style, typography, and asset contracts
over the same state snapshot:

```ts
// Target model only — these grouped contract families and non-geometry helpers
// are not released bylaw-ui APIs.
const report = evaluateSnapshot(snapshot, {
  geometry: [
    width("sidebar", { minPx: 260, maxPx: 280 }),
    inside("viewed-control", "changed-file"),
  ],
  style: [backgroundColor("toolbar", "#ffffff")],
  typography: [fontSize("filename", { minPx: 13, maxPx: 14 })],
  assets: [assetSource("expand-icon", "/icons/chevron-right.svg")],
});
```

This conceptual API illustrates the direction, not a promise of exact future
names or signatures. The current-API example above is the closest shipped
equivalent: it evaluates many geometry rules against one immediate snapshot and
returns all findings together.

## Related implementation work

- [#175 — Support logical targets and scoped locators](https://github.com/ryanzidago/bylaw/issues/175)
- [#176 — Include measured geometry in assertion errors](https://github.com/ryanzidago/bylaw/issues/176)
- [#177 — Add first-class collection geometry rules](https://github.com/ryanzidago/bylaw/issues/177)
- [#178 — Add unary absolute and viewport geometry rules](https://github.com/ryanzidago/bylaw/issues/178)
- [#179 — Add an opt-in Playwright layout readiness helper](https://github.com/ryanzidago/bylaw/issues/179)
- [#180 — Expose a validated public adapter boundary](https://github.com/ryanzidago/bylaw/issues/180)

These issues own their implementation contracts. This README describes how
their capabilities fit the state-snapshot usage model without redefining them.

## Geometry contract

- Relationship helpers use `subject, reference` argument order.
- Unary geometry helpers evaluate a single target: `width(target, range)`,
  `height(target, range)`, and `inViewport(target)`.
- Measurements use viewport-relative `Element.getBoundingClientRect()` border
  rectangles in fractional CSS pixels.
- Registered locators resolve immediately from the current page state without
  Playwright auto-waiting or DOM mutation.
- Fallback test IDs are exact and case-sensitive. Whitespace is preserved.
- Every check measures all referenced elements in one browser-side snapshot.
- Missing, duplicate, hidden, and zero-size elements are report findings rather
  than arbitrary element selection or implicit waiting.
- The package root has no Playwright runtime dependency or browser side effects.

The current release verifies alignment, directional ordering and gaps, overlap
depth, non-overlap, containment, width, height, and size. It does not yet judge
typography, color, hierarchy, aesthetics, occlusion, or irregular shapes.

Use unary width and height rules for absolute pixel constraints. Prefer the
relative `sameWidth`, `sameHeight`, and `sameSize` rules when the contract is
that two rendered elements should match.

## Public adapter

Use `createAdapter` to connect another measurement platform, such as CDP,
WebDriver, MCP, or a static-layout source, without importing Playwright or
private Bylaw modules:

```ts
import { checkLayout, createAdapter, width } from "bylaw-ui";

const adapter = createAdapter({
  async measure(targets) {
    return {
      viewport: { width: 1280, height: 720 },
      targets: targets.map((target) => ({
        target,
        matchCount: 1,
        hidden: false,
        rect: { x: 0, y: 0, width: 240, height: 48 },
      })),
    };
  },
});

const report = await checkLayout({
  adapter,
  rules: [width("sidebar", { minPx: 200 })],
});
```

Adapter measurements are normalized CSS-pixel data. Rectangles are viewport-relative,
axis-aligned border-box bounds and may use fractional CSS pixels or negative `x` and
`y` coordinates. Viewport dimensions must be positive and finite; rectangle
dimensions must be nonnegative and finite.

A singular target uses `matchCount: 0` when missing, `matchCount: 1` with
`hidden` and `rect` when resolved, and a count greater than one when ambiguous.
A collection target uses `matches`, including an empty collection when it has
no members. Results must correlate one-to-one with the targets requested by
Bylaw.

Collection results are part of the public measurement compatibility boundary,
but the current package does not export collection evaluation rules. Do not
expect a current rule to evaluate every member: one member resolves as a
singular target, an empty collection is missing, and multiple members are
ambiguous. Follow [#177](https://github.com/ryanzidago/bylaw/issues/177) for the
planned collection-rule API.

Malformed snapshots throw `MeasurementValidationError` before any rule is
evaluated and never become layout findings or partial reports. Errors thrown or
rejections returned by the adapter's measurement platform propagate unchanged.

The adapter or underlying platform owns target discovery and any waiting needed
before measurement. The public adapter is not responsible for relationship inference
or aesthetic evaluation; Bylaw evaluates only the explicit geometric rules supplied
by the caller.

## License

MIT
