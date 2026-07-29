import { expect, test } from "bun:test";

import {
  assertLayout,
  checkLayout,
  LayoutAssertionError,
  sameWidth,
} from "bylaw-ui";

import { fixtureAdapter, rect, visible } from "./support";

async function sameWidthFailure(): Promise<LayoutAssertionError> {
  const report = await checkLayout({
    adapter: fixtureAdapter({
      avatar: visible("avatar", rect(0, 0, 98, 20)),
      card: visible("card", rect(0, 0, 100, 20)),
    }),
    rules: [sameWidth("avatar", "card")],
  });

  try {
    assertLayout(report);
  } catch (error) {
    expect(error).toBeInstanceOf(LayoutAssertionError);
    return error as LayoutAssertionError;
  }

  throw new Error("Expected the unequal widths to fail the layout assertion");
}

/**
 * Issue: Production size findings omit the raw subject and reference dimensions
 * that the assertion formatter needs.
 * Why it matters: Callers cannot see the measured operands that produced a size
 * mismatch, so the diagnostic is not actionable without inspecting the page.
 */
test("size diagnostics from checkLayout report both measured operand widths", async () => {
  const error = await sameWidthFailure();

  expect(error.message).toContain("subject width: 98px");
  expect(error.message).toContain("reference width: 100px");
});

/**
 * Issue: A sameWidth finding includes the irrelevant height difference in its
 * rendered diagnostic.
 * Why it matters: Real sameWidth failures can display two identically labelled
 * difference lines, including a passing height measurement that looks like a
 * second width result.
 */
test("sameWidth diagnostics render only the width difference", async () => {
  const error = await sameWidthFailure();
  const differenceLines = error.message
    .split("\n")
    .filter((line) => line.startsWith("difference:"));

  expect(differenceLines).toEqual(["difference: 2px"]);
});
