# bylaw-ui API cheatsheet

Use this page to look up the released `bylaw-ui` API. See the
[README](README.md) for installation, concepts, ownership boundaries, and
extended examples.

The current release evaluates objective geometry contracts. It does not judge
typography, color, visual hierarchy, aesthetics, occlusion, or irregular
shapes.

## Minimal Playwright example

```ts
// Keep browser-independent contracts separate from the Playwright integration.
import { assertLayout, checkLayout, inside, leftOf, width } from "bylaw-ui";
import { playwright, waitForLayoutTargets } from "bylaw-ui/playwright";

// Describe the intended geometry with stable logical names so the contracts
// remain readable when selectors change.
const rules = [
  width("sidebar", { minPx: 260, maxPx: 280 }),
  leftOf("sidebar", "content", { gap: { minPx: 8 } }),
  inside("save-button", "toolbar"),
];

// Map logical names to semantic locators without changing production markup.
const adapter = playwright(page, {
  targets: {
    sidebar: page.getByRole("navigation"),
    content: page.getByRole("main"),
    toolbar: page.getByRole("toolbar"),
    "save-button": page.getByRole("button", { name: "Save" }),
  },
});

// Wait explicitly for measured geometry to settle so animation or rendering
// does not produce a transient snapshot.
await waitForLayoutTargets(adapter, rules, {
  timeoutMs: 1_000,
  stableFrames: 2,
});

// Measure once, evaluate every rule, and fail the surrounding test if needed.
assertLayout(await checkLayout({ adapter, rules }));
```

Evaluate all contracts for one rendered state in a single `checkLayout` call.

## Entrypoints

| Import                | Provides                                                               |
| --------------------- | ---------------------------------------------------------------------- |
| `bylaw-ui`            | Rules, evaluator, assertion, public adapter factory, errors, and types |
| `bylaw-ui/playwright` | Playwright adapter, layout-readiness helper, related error, and types  |

## Singular geometry rules

Binary rules always take `subject, reference` in that order.

| Capability             | Helper                                           | Options                      |
| ---------------------- | ------------------------------------------------ | ---------------------------- |
| Align edges or centers | `align(subject, reference, alignment, options?)` | `{ tolerancePx? }`           |
| Place above            | `above(subject, reference, options?)`            | `{ tolerancePx?, gap? }`     |
| Place below            | `below(subject, reference, options?)`            | `{ tolerancePx?, gap? }`     |
| Place left             | `leftOf(subject, reference, options?)`           | `{ tolerancePx?, gap? }`     |
| Place right            | `rightOf(subject, reference, options?)`          | `{ tolerancePx?, gap? }`     |
| Require overlap        | `overlap(subject, reference, options?)`          | `{ horizontal?, vertical? }` |
| Prohibit overlap       | `notOverlap(subject, reference)`                 | None                         |
| Require containment    | `inside(subject, reference, options?)`           | `{ tolerancePx? }`           |
| Match width            | `sameWidth(subject, reference, options?)`        | `{ tolerancePx? }`           |
| Match height           | `sameHeight(subject, reference, options?)`       | `{ tolerancePx? }`           |
| Match width and height | `sameSize(subject, reference, options?)`         | `{ tolerancePx? }`           |
| Constrain width        | `width(target, range)`                           | Inclusive pixel range        |
| Constrain height       | `height(target, range)`                          | Inclusive pixel range        |
| Keep inside viewport   | `inViewport(target)`                             | None                         |

Alignments are `"left"`, `"right"`, `"top"`, `"bottom"`, `"centerX"`, and
`"centerY"`.

## Collection geometry rules

Declare collection intent once, then pass the resulting target to collection
rules:

```ts
// Mark this logical target as a collection because collection rules evaluate
// every matched card instead of requiring exactly one match.
const cards = collection("card");
```

| Capability                 | Helper                                         | Options            |
| -------------------------- | ---------------------------------------------- | ------------------ |
| Contain every member       | `everyInside(collection, container, options?)` | `{ tolerancePx? }` |
| Match every member's width | `equalWidths(collection, options?)`            | `{ tolerancePx? }` |
| Order members vertically   | `verticallyOrdered(collection, options?)`      | `{ gap? }`         |
| Prohibit pairwise overlap  | `pairwiseNotOverlap(collection)`               | None               |

Collection evaluation follows adapter target order. Member indexes are
zero-based. `equalWidths` uses the first member as the reference, and
`verticallyOrdered` compares adjacent members.

## Option shapes

```ts
type PixelRange = {
  // Set either inclusive bound or both to express the allowed measurement.
  minPx?: number;
  maxPx?: number;
};

type ToleranceOptions = {
  // Allow small rendering differences without weakening the core contract.
  tolerancePx?: number;
};

type OrderingOptions = {
  // Tolerance permits slight boundary crossing; gap constrains valid spacing.
  tolerancePx?: number;
  gap?: PixelRange;
};

type OverlapOptions = {
  // Constrain overlap depth independently on each axis when depth matters.
  horizontal?: PixelRange;
  vertical?: PixelRange;
};
```

Pixel ranges are inclusive. Supply `minPx`, `maxPx`, or both. Geometry uses
fractional CSS pixels from viewport-relative `getBoundingClientRect()` border
rectangles.

## Evaluation and assertion

```ts
// Keep the structured report when another tool or agent needs every finding.
const report = await checkLayout({ adapter, rules });

if (!report.passed) {
  console.error(report.findings);
}

// Convert the same report into a test failure at the test-runner boundary.
assertLayout(report);
```

| API                               | Behavior                                                  |
| --------------------------------- | --------------------------------------------------------- |
| `checkLayout({ adapter, rules })` | Measures one snapshot and returns `Promise<LayoutReport>` |
| `assertLayout(report)`            | Returns for a passing report; otherwise throws            |

`LayoutAssertionError` retains the original structured report on its `report`
property.

Report outcomes:

- Invalid rules and geometry violations are `failed`.
- Missing, duplicate, hidden, zero-size, or empty-collection targets are
  `skipped`.
- A report passes only when every rule passes and `findings` is empty.
- Independent findings remain in supplied rule order.

Exceptions are reserved for boundary failures:

- Rule helpers and invalid call shapes throw `TypeError`.
- Malformed custom-adapter snapshots throw `MeasurementValidationError`.
- Browser and adapter exceptions propagate unchanged.

## Playwright targets

```ts
// Register semantic locators so contracts use stable product concepts instead
// of coupling target names to CSS selectors or DOM structure.
const adapter = playwright(page, {
  targets: {
    toolbar: page.getByRole("toolbar"),
    "save-button": page.getByRole("button", { name: "Save" }),
  },
});
```

- Registered locators resolve immediately without Playwright auto-waiting.
- Singular targets require exactly one match.
- A registered locator wins even when it resolves to zero or multiple elements.
- Unregistered names fall back to exact, case-sensitive `data-testid` values.
- Collection rules accept every match in locator order.
- Only targets referenced by the supplied rules are measured.

## Layout readiness

```ts
import {
  LayoutReadinessTimeoutError,
  waitForLayoutTargets,
} from "bylaw-ui/playwright";

try {
  // Stabilize only the geometry referenced by these rules before measuring it.
  await waitForLayoutTargets(adapter, rules, {
    timeoutMs: 1_000,
    stableFrames: 2,
  });
} catch (error) {
  if (error instanceof LayoutReadinessTimeoutError) {
    // Preserve timeout diagnostics so an agent can distinguish missing targets
    // from targets that exist but continue moving.
    console.error(error.unresolvedTargets);
    console.error(error.unstableTargets);
    console.error(error.lastObserved);
  }

  // Readiness is a platform failure, so let the surrounding test handle it.
  throw error;
}
```

`waitForLayoutTargets` accepts only an adapter returned by `playwright`. It
waits for referenced targets to resolve and for required geometry to stabilize;
it does not assert visibility, positive size, or contract compliance.

## Custom adapters

Use `createAdapter(implementation)` from `bylaw-ui` to connect another
measurement platform. Custom adapters own platform-specific target resolution,
snapshot collection, and waiting. Their snapshots are validated before
contract evaluation.

See [Public adapter](README.md#public-adapter) for the full measurement
contract.
