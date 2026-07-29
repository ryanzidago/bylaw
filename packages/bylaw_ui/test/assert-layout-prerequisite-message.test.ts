import { expect, test } from "bun:test";

import {
  checkLayout,
  LayoutAssertionError,
  sameSize,
  type LayoutReport,
  type LayoutRule,
} from "bylaw-ui";
import { fixtureAdapter, hidden, rect, unresolved, visible } from "./support";

function failureMessage(report: LayoutReport): string {
  expect(report.passed).toBe(false);
  return new LayoutAssertionError(report).message;
}

test("reports an invalid rule field and reason", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({}),
    rules: [
      {
        kind: "sameSize",
        subject: "avatar",
        reference: "card",
        surprise: true,
      } as LayoutRule,
    ],
  });

  const message = failureMessage(report);
  expect(message).toContain("invalid rule");
  expect(message).toContain("field: surprise");
  expect(message).toContain("reason: is not supported");
});

test("reports a missing element and its operand role", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: unresolved("avatar", 0),
      card: visible("card", rect()),
    }),
    rules: [sameSize("avatar", "card")],
  });

  const message = failureMessage(report);
  expect(message).toContain("missing element");
  expect(message).toContain('subject: "avatar"');
  expect(message).toContain("expected matches: 1");
  expect(message).toContain("actual matches: 0");
});

test("reports duplicate element matches and their operand role", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect()),
      card: unresolved("card", 3),
    }),
    rules: [sameSize("avatar", "card")],
  });

  const message = failureMessage(report);
  expect(message).toContain("duplicate element");
  expect(message).toContain('reference: "card"');
  expect(message).toContain("expected matches: 1");
  expect(message).toContain("actual matches: 3");
});

test("reports a hidden element and its measured dimensions", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: hidden("avatar", rect(0, 0, 96, 48)),
      card: visible("card", rect()),
    }),
    rules: [sameSize("avatar", "card")],
  });

  const message = failureMessage(report);
  expect(message).toContain("hidden element");
  expect(message).toContain('subject: "avatar"');
  expect(message).toContain("measured width: 96px");
  expect(message).toContain("measured height: 48px");
});

test("reports a zero-size element and its measured dimensions", async () => {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(0, 0, 0, 48)),
      card: visible("card", rect()),
    }),
    rules: [sameSize("avatar", "card")],
  });

  const message = failureMessage(report);
  expect(message).toContain("zero-size element");
  expect(message).toContain('subject: "avatar"');
  expect(message).toContain("measured width: 0px");
  expect(message).toContain("measured height: 48px");
});
