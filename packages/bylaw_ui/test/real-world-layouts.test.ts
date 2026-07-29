import { expect, test } from "bun:test";

import {
  align,
  checkLayout,
  inside,
  leftOf,
  overlap,
  sameWidth,
} from "bylaw-ui";
import { fixtureAdapter, rect, visible } from "./support";

test("validates an avatar aligned with a timeline and separated by a bounded gap", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(16, 20, 40, 40)),
      timeline: visible("timeline", rect(64, 0, 2, 80)),
    }),
    rules: [
      align("avatar", "timeline", "centerY"),
      leftOf("avatar", "timeline", { gap: { minPx: 8, maxPx: 16 } }),
    ],
  });
  expect(report.passed).toBe(true);
});

test("reports a timeline item whose avatar crosses the timeline boundary", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(30, 20, 40, 40)),
      timeline: visible("timeline", rect(64, 0, 2, 80)),
    }),
    rules: [leftOf("avatar", "timeline")],
  });
  expect(report.findings[0]?.code).toBe("ordering-violation");
});

test("validates a status badge overlapping an avatar by a required depth", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(0, 0, 48, 48)),
      badge: visible("badge", rect(36, 36, 16, 16)),
    }),
    rules: [
      overlap("badge", "avatar", {
        horizontal: { minPx: 12 },
        vertical: { minPx: 12 },
      }),
    ],
  });
  expect(report.passed).toBe(true);
});

test("reports a status badge that only touches the avatar edge", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(0, 0, 48, 48)),
      badge: visible("badge", rect(48, 48, 16, 16)),
    }),
    rules: [overlap("badge", "avatar")],
  });
  expect(report.findings[0]?.code).toBe("missing-overlap");
});

test("validates equal-width cards in a responsive grid", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      first: visible("first", rect(0, 0, 240, 160)),
      second: visible("second", rect(256, 0, 240, 220)),
      third: visible("third", rect(512, 0, 240, 180)),
    }),
    rules: [sameWidth("first", "second"), sameWidth("second", "third")],
  });
  expect(report.rules.passed).toBe(2);
});

test("reports one incorrectly sized card among otherwise equal cards", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      first: visible("first", rect(0, 0, 240, 160)),
      second: visible("second", rect(256, 0, 241, 220)),
      third: visible("third", rect(512, 0, 240, 180)),
    }),
    rules: [sameWidth("first", "third"), sameWidth("first", "second")],
  });
  expect(report.rules).toMatchObject({ passed: 1, failed: 1 });
});

test("validates a control contained within a panel at exact boundaries", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      control: visible("control", rect(0, 0, 320, 48)),
      panel: visible("panel", rect(0, 0, 320, 48)),
    }),
    rules: [inside("control", "panel")],
  });
  expect(report.passed).toBe(true);
});

test("reports a control overflowing one side of its panel", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      control: visible("control", rect(0, 0, 321, 48)),
      panel: visible("panel", rect(0, 0, 320, 48)),
    }),
    rules: [inside("control", "panel")],
  });
  expect(report.findings[0]).toMatchObject({
    code: "containment-overflow",
    actual: { rightPx: 1 },
  });
});

test("returns several actionable findings from one broken page layout", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(40, 10, 48, 48)),
      timeline: visible("timeline", rect(64, 0, 2, 100)),
      badge: visible("badge", rect(88, 58, 16, 16)),
      panel: visible("panel", rect(0, 120, 320, 80)),
      control: visible("control", rect(-2, 120, 324, 80)),
    }),
    rules: [
      leftOf("avatar", "timeline"),
      overlap("badge", "avatar"),
      inside("control", "panel"),
    ],
  });
  expect(report.findings.map(({ code }) => code)).toEqual([
    "ordering-violation",
    "missing-overlap",
    "containment-overflow",
  ]);
});

test("evaluates separate rule sets after callers configure different viewports", async () => {
  const desktop = await checkLayout({
    adapter: fixtureAdapter({
      first: visible("first", rect(0, 0, 300, 200)),
      second: visible("second", rect(320, 0, 300, 200)),
    }),
    rules: [sameWidth("first", "second")],
  });
  const mobile = await checkLayout({
    adapter: fixtureAdapter({
      first: visible("first", rect(0, 0, 280, 200)),
      second: visible("second", rect(0, 220, 280, 200)),
    }),
    rules: [sameWidth("first", "second")],
  });
  expect([desktop.passed, mobile.passed]).toEqual([true, true]);
});
