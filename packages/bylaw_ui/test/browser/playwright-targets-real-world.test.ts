import { expect, test } from "bun:test";

import { checkLayout, inside } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import { browserHarness, expectPassed } from "./logical-target-support";

const withPage = browserHarness();

test("checks a file row scoped within the changed-files container without modifying production markup", () =>
  withPage(
    `
      <main>
        <section aria-label="Changed files" class="changed-files" style="position:relative;width:600px;height:200px;padding:16px">
          <article class="file-row" style="width:568px;height:48px">
            <a href="/src/example.ts">src/example.ts</a>
          </article>
        </section>
        <aside><article class="file-row">Unrelated row</article></aside>
      </main>
    `,
    async (page) => {
      const before = await page.locator("main").evaluate((element) => element.outerHTML);
      const changedFiles = page.getByRole("region", { name: "Changed files" });
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            changedFiles,
            changedFileRow: changedFiles
              .locator(".file-row")
              .filter({ hasText: "src/example.ts" }),
          },
        }),
        rules: [inside("changedFileRow", "changedFiles")],
      });
      expectPassed(report);
      expect(await page.locator("[data-testid]").count()).toBe(0);
      expect(
        await page.locator("main").evaluate((element) => element.outerHTML),
      ).toBe(before);
    },
  ));
