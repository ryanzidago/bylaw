import { expect, test } from "bun:test";
import type { ElementHandle, Locator, Page } from "playwright-core";

import { checkLayout, sameSize } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";

/**
 * Issue: Resolved element handles leak when another registered locator rejects.
 * Why it matters: Repeated failed checks retain browser-side objects and can
 * exhaust Playwright resources in a long-running test process.
 */
test("disposes resolved element handles when another registered target fails", async () => {
  let disposals = 0;
  const handle = {
    dispose: async () => {
      disposals += 1;
    },
  } as ElementHandle;
  const resolutionFailure = new Error("registered locator failed");
  const resolved = {
    elementHandles: async () => [handle],
  } as unknown as Locator;
  const rejected = {
    elementHandles: async () => {
      await Promise.resolve();
      throw resolutionFailure;
    },
  } as unknown as Locator;
  const page = {
    evaluate: async () => {
      throw new Error("measurement must not run after locator failure");
    },
  } as unknown as Page;

  const caught = await checkLayout({
    adapter: playwright(page, {
      targets: { resolved, rejected },
    }),
    rules: [sameSize("resolved", "rejected")],
  }).catch((error: unknown) => error);

  expect(caught).toBe(resolutionFailure);
  expect(disposals).toBe(1);
});
