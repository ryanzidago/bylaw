import { expect, test } from "bun:test";

/**
 * @doc Issue: Playwright readiness accepts an unpublished
 * `collectionEqualWidth` rule through a private `LegacyCollectionRule` path.
 * Why it matters: Pre-release compatibility code creates a second collection
 * rule model that can drift from the public API without serving any users.
 */
test("Playwright readiness has no compatibility path for unpublished collection rules", async () => {
  const source = await Bun.file(
    new URL("../../src/playwright.ts", import.meta.url),
  ).text();

  expect(source).not.toContain("LegacyCollectionRule");
  expect(source).not.toContain("collectionEqualWidth");
});
