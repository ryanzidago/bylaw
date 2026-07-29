import { expect, test } from "bun:test";

import { align, checkLayout, inside, sameSize, sameWidth } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import { browserHarness, expectPassed } from "./logical-target-support";

const withPage = browserHarness();

test("resolves a rule subject from a registered Playwright locator", () =>
  withPage(
    '<div class="actual" style="width:20px;height:20px"></div><div data-testid="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { subject: page.locator(".actual") },
        }),
        rules: [sameSize("subject", "reference")],
      });
      expectPassed(report);
    },
  ));

test("resolves a rule reference from a registered Playwright locator", () =>
  withPage(
    '<div data-testid="subject" style="width:20px;height:20px"></div><div class="actual" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { reference: page.locator(".actual") },
        }),
        rules: [sameSize("subject", "reference")],
      });
      expectPassed(report);
    },
  ));

test("resolves multiple logical names from registered Playwright locators", () =>
  withPage(
    '<div class="one" style="width:20px;height:20px"></div><div class="two" style="width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            first: page.locator(".one"),
            second: page.locator(".two"),
          },
        }),
        rules: [sameSize("first", "second")],
      });
      expectPassed(report);
    },
  ));

test("reuses one registered target across multiple rules", () =>
  withPage(
    '<div class="shared" style="position:absolute;width:20px;height:20px"></div><div class="peer" style="position:absolute;width:20px;height:20px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            shared: page.locator(".shared"),
            peer: page.locator(".peer"),
          },
        }),
        rules: [
          sameSize("shared", "peer"),
          sameWidth("shared", "peer"),
          align("shared", "peer", "top"),
        ],
      });
      expectPassed(report, 3);
    },
  ));

test("supports semantic role locators without data-testid attributes", () =>
  withPage(
    '<button style="width:100px;height:30px">Save changes</button><div class="peer" style="width:100px;height:30px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            action: page.getByRole("button", { name: "Save changes" }),
            peer: page.locator(".peer"),
          },
        }),
        rules: [sameSize("action", "peer")],
      });
      expectPassed(report);
    },
  ));

test("supports composed Playwright locators", () =>
  withPage(
    '<section aria-label="Account"><button style="width:80px;height:24px">Edit</button></section><div class="peer" style="width:80px;height:24px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            edit: page
              .getByRole("region", { name: "Account" })
              .getByRole("button", { name: "Edit" }),
            peer: page.locator(".peer"),
          },
        }),
        rules: [sameSize("edit", "peer")],
      });
      expectPassed(report);
    },
  ));

/**
 * Issue: A registered locator inside an iframe is measured in frame-local
 * coordinates instead of top-level viewport coordinates.
 * Why it matters: The public registry accepts Playwright Locator values without
 * excluding frame locators, but common embedded UI targets fail at runtime.
 */
test("measures registered Playwright locators in top-level viewport coordinates", () =>
  withPage(
    '<iframe title="Embedded UI" style="position:absolute;left:100px;top:100px;border:0" srcdoc="<style>html,body{margin:0}</style><button style=&quot;width:80px;height:24px&quot;>Edit</button>"></iframe><div class="peer" style="position:absolute;left:100px;top:100px;width:80px;height:24px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            edit: page
              .frameLocator('iframe[title="Embedded UI"]')
              .getByRole("button", { name: "Edit" }),
            peer: page.locator(".peer"),
          },
        }),
        rules: [
          sameSize("edit", "peer"),
          align("edit", "peer", "left"),
          align("edit", "peer", "top"),
        ],
      });
      expectPassed(report, 3);
    },
  ));

/**
 * Issue: Registered targets inside transformed iframes retain their unscaled
 * frame-local dimensions.
 * Why it matters: Rules report false geometry findings when an embedded UI is
 * rendered through a CSS transform.
 */
test("measures registered targets through transformed iframes", () =>
  withPage(
    '<iframe title="Scaled UI" style="position:absolute;left:100px;top:100px;width:200px;height:100px;border:0;transform:scale(2);transform-origin:top left" srcdoc="<style>html,body{margin:0}</style><button style=&quot;width:80px;height:24px&quot;>Edit</button>"></iframe><div class="peer" style="position:absolute;left:100px;top:100px;width:160px;height:48px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            edit: page
              .frameLocator('iframe[title="Scaled UI"]')
              .getByRole("button", { name: "Edit" }),
            peer: page.locator(".peer"),
          },
        }),
        rules: [
          sameSize("edit", "peer"),
          align("edit", "peer", "left"),
          align("edit", "peer", "top"),
        ],
      });
      expectPassed(report, 3);
    },
  ));

/**
 * Issue: Registered handles from cross-origin frames cannot be adopted by the
 * top-level page evaluation.
 * Why it matters: Valid Playwright frame locators throw instead of producing a
 * layout report for embedded third-party UI.
 */
test("measures registered targets inside cross-origin iframes", () =>
  withPage(
    '<iframe title="External UI" style="position:absolute;left:100px;top:100px;border:0" src="data:text/html,<style>html,body{margin:0}</style><button style=width:80px;height:24px>Edit</button>"></iframe><div class="peer" style="position:absolute;left:100px;top:100px;width:80px;height:24px"></div>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            edit: page
              .frameLocator('iframe[title="External UI"]')
              .getByRole("button", { name: "Edit" }),
            peer: page.locator(".peer"),
          },
        }),
        rules: [
          sameSize("edit", "peer"),
          align("edit", "peer", "left"),
          align("edit", "peer", "top"),
        ],
      });
      expectPassed(report, 3);
    },
  ));

test("does not require logical target names to match DOM attributes", () =>
  withPage(
    '<main id="production-shell" style="width:200px;height:100px"><span class="item" style="display:block;width:40px;height:20px"></span></main>',
    async (page) => {
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            "logical container": page.locator("#production-shell"),
            "logical child": page.locator(".item"),
          },
        }),
        rules: [inside("logical child", "logical container")],
      });
      expectPassed(report);
      expect(await page.locator("[data-testid]").count()).toBe(0);
    },
  ));

test("does not mutate the DOM while resolving registered targets", () =>
  withPage(
    '<div id="root"><div class="subject" style="width:20px;height:20px"></div><div class="reference" style="width:20px;height:20px"></div></div>',
    async (page) => {
      const before = await page
        .locator("#root")
        .evaluate((element) => element.outerHTML);
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: {
            subject: page.locator(".subject"),
            reference: page.locator(".reference"),
          },
        }),
        rules: [sameSize("subject", "reference")],
      });
      expectPassed(report);
      expect(
        await page.locator("#root").evaluate((element) => element.outerHTML),
      ).toBe(before);
    },
  ));
