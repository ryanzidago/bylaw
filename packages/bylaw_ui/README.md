# bylaw-ui

`bylaw-ui` turns objective rendered layout relationships into executable,
machine-readable checks. It measures elements identified by logical Playwright
targets or exact `data-testid` values and evaluates their geometry without
screenshot analysis.

## Install

```sh
npm install bylaw-ui playwright-core
```

Chromium is the verified V1 browser target. Install the browser build matching
your Playwright version:

```sh
npx playwright-core install chromium
```

## Use

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
  overlap,
  width,
} from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";

const report = await checkLayout({
  adapter: playwright(page),
  rules: [
    align("avatar-icon", "timeline", "centerY", {
      tolerancePx: 1,
    }),
    leftOf("avatar-icon", "timeline", {
      gap: { minPx: 8, maxPx: 16 },
    }),
    overlap("status-badge", "avatar", {
      horizontal: { minPx: 8 },
      vertical: { minPx: 8 },
    }),
    inside("status-badge", "avatar", {
      tolerancePx: 4,
    }),
    width("sidebar", { minPx: 260, maxPx: 320 }),
    height("toolbar", { minPx: 48 }),
    inViewport("dialog"),
  ],
});

assertLayout(report);
```

Register Playwright locators when rule operands should not depend on production
markup. Locator composition keeps descendant addressing scoped to its
container:

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

`checkLayout` returns all independent invalid-rule, element-resolution,
visibility, and geometry findings in one JSON-serializable report. Use
`assertLayout` when a failing report should throw `LayoutAssertionError`; the
error retains the original report by identity.

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

V1 verifies alignment, directional ordering and gaps, overlap depth,
non-overlap, containment, width, height, and size. It does not judge typography,
color, hierarchy, aesthetics, occlusion, or irregular shapes.

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

Malformed snapshots throw `MeasurementValidationError` before any rule is
evaluated and never become layout findings or partial reports. Errors thrown or
rejections returned by the adapter's measurement platform propagate unchanged.

The adapter or underlying platform owns target discovery and any waiting needed
before measurement. The public adapter is not responsible for relationship inference
or aesthetic evaluation; Bylaw evaluates only the explicit geometric rules supplied
by the caller.

## License

MIT
