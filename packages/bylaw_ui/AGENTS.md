# Bylaw UI

Guidance specific to `packages/bylaw_ui`.

## Product Boundary

Keep the public API extremely narrow, expressive, and predictable.

Bylaw UI answers one question:

> Given measured rectangles and declared geometric relationships, which
> relationships hold?

Bylaw UI owns objective geometry contracts, including alignment, ordering,
containment, overlap, dimensions, viewport relationships, and collection
geometry.

The surrounding test framework owns:

- Browser and application-state orchestration.
- Content and product-cardinality assertions.
- Interaction behavior.
- Accessibility semantics.
- Performance.
- Screenshot and visual-fidelity comparison.
- General data validation.

Prefer ordinary Playwright assertions whenever they express a requirement
clearly. Add Bylaw UI API only when the requirement is fundamentally geometric
and raw browser geometry would be materially less expressive or diagnostic.

## Public API Discipline

- Do not add a new rule, helper, option, abstraction, or orchestration API for a
  single consumer or hypothetical future use.
- Require repeated concrete usage before expanding the public API.
- Prefer improving diagnostics and implementation internals over adding DSL
  surface area.
- Preserve one preferred workflow:
  1. The consumer renders the intended state.
  2. An adapter captures one coherent geometry snapshot.
  3. Bylaw evaluates many pure contracts.
  4. Structured diagnostics guide repair.
- Keep the package root browser-independent.
- Keep Playwright-specific behavior in the Playwright adapter entrypoint.
- Keep readiness optional and explicit. Do not make Bylaw own navigation,
  authentication, fixtures, or application-specific waiting.
- Do not duplicate assertions already expressed clearly by Playwright.
- Avoid convenience APIs that combine distinct phases unless repeated usage
  demonstrates that the explicit operations are inadequate.

Before adding public API, document:

- The concrete recurring geometric problem.
- Why the existing API cannot express it.
- Why Playwright alone is materially worse.
- The smallest general addition that solves it.
- How the addition preserves the existing mental model.
- What remains explicitly out of scope.

If those questions do not have strong answers, do not expand the API.
