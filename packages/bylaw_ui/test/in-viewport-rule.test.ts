import { expect, test } from "bun:test";

import { checkLayout, inViewport } from "bylaw-ui";
import { createInternalAdapter } from "../src/internal/adapter";
import { rect, visible } from "./support";

const viewport = { width: 100, height: 80 };

function viewportAdapter(
  targetRect: ReturnType<typeof rect>,
  currentViewport = viewport,
) {
  return createInternalAdapter(async (testIds) => ({
    viewport: currentViewport,
    elements: testIds.map((testId) => visible(testId, targetRect)),
  }));
}

async function checkViewport(
  targetRect: ReturnType<typeof rect>,
  currentViewport = viewport,
) {
  return checkLayout({
    adapter: viewportAdapter(targetRect, currentViewport),
    rules: [inViewport("target")],
  });
}

async function expectViewportPass(targetRect: ReturnType<typeof rect>) {
  const report = await checkViewport(targetRect);
  expect(report).toMatchObject({
    passed: true,
    rules: { total: 1, passed: 1, failed: 0, skipped: 0 },
    findings: [],
  });
}

async function expectViewportFailure(targetRect: ReturnType<typeof rect>) {
  const report = await checkViewport(targetRect);
  expect(report).toMatchObject({
    passed: false,
    rules: { total: 1, passed: 0, failed: 1, skipped: 0 },
  });
  expect(report.findings).toContainEqual(
    expect.objectContaining({
      category: "layout",
      relationship: "inViewport",
      target: "target",
      expected: {
        viewport: { leftPx: 0, topPx: 0, rightPx: 100, bottomPx: 80 },
      },
      actual: {
        target: {
          leftPx: targetRect.x,
          topPx: targetRect.y,
          rightPx: targetRect.x + targetRect.width,
          bottomPx: targetRect.y + targetRect.height,
        },
      },
    }),
  );
}

test("inViewport accepts a target strictly inside the viewport", () =>
  expectViewportPass(rect(10, 10, 20, 20)));

test("inViewport accepts a target sharing the viewport left edge", () =>
  expectViewportPass(rect(0, 10, 20, 20)));

test("inViewport accepts a target sharing the viewport top edge", () =>
  expectViewportPass(rect(10, 0, 20, 20)));

test("inViewport accepts a target sharing the viewport right edge", () =>
  expectViewportPass(rect(80, 10, 20, 20)));

test("inViewport accepts a target sharing the viewport bottom edge", () =>
  expectViewportPass(rect(10, 60, 20, 20)));

test("inViewport accepts a target sharing every viewport edge", () =>
  expectViewportPass(rect(0, 0, 100, 80)));

test("inViewport rejects a target partially clipped beyond the viewport left edge", () =>
  expectViewportFailure(rect(-0.25, 10, 20, 20)));

test("inViewport rejects a target partially clipped beyond the viewport top edge", () =>
  expectViewportFailure(rect(10, -0.25, 20, 20)));

test("inViewport rejects a target partially clipped beyond the viewport right edge", () =>
  expectViewportFailure(rect(80.25, 10, 20, 20)));

test("inViewport rejects a target partially clipped beyond the viewport bottom edge", () =>
  expectViewportFailure(rect(10, 60.25, 20, 20)));

test("inViewport rejects a target fully off-screen to the left", () =>
  expectViewportFailure(rect(-30, 10, 20, 20)));

test("inViewport rejects a target fully off-screen above the viewport", () =>
  expectViewportFailure(rect(10, -30, 20, 20)));

test("inViewport rejects a target fully off-screen to the right", () =>
  expectViewportFailure(rect(100, 10, 20, 20)));

test("inViewport rejects a target fully off-screen below the viewport", () =>
  expectViewportFailure(rect(10, 80, 20, 20)));

test("inViewport rejects a target clipped beyond two viewport edges", () =>
  expectViewportFailure(rect(-1, -2, 20, 20)));

test("inViewport rejects a target larger than the viewport", () =>
  expectViewportFailure(rect(-1, -1, 102, 82)));

test("inViewport evaluates against the viewport captured with the target", async () => {
  const adapter = createInternalAdapter(async (testIds) => ({
    viewport: { width: 40, height: 30 },
    elements: testIds.map((testId) => visible(testId, rect(0, 0, 50, 20))),
  }));
  const report = await checkLayout({
    adapter,
    rules: [inViewport("target")],
  });
  expect(report.passed).toBe(false);
  expect(report.findings[0]).toMatchObject({
    expected: {
      viewport: { leftPx: 0, topPx: 0, rightPx: 40, bottomPx: 30 },
    },
  });
});

test("inViewport observes viewport changes between separate checks", async () => {
  let currentViewport = { width: 100, height: 80 };
  const adapter = createInternalAdapter(async (testIds) => ({
    viewport: currentViewport,
    elements: testIds.map((testId) => visible(testId, rect(0, 0, 100, 80))),
  }));
  const rule = inViewport("target");

  expect((await checkLayout({ adapter, rules: [rule] })).passed).toBe(true);
  currentViewport = { width: 99, height: 79 };
  expect((await checkLayout({ adapter, rules: [rule] })).passed).toBe(false);
});
