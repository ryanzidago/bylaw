import { expect, test } from "bun:test";
import type { ElementHandle, Locator, Page } from "playwright-core";

import {
  checkLayout,
  collection,
  equalWidths,
  everyInside,
} from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";
import { browserHarness, expectPassed } from "./logical-target-support";

const withPage = browserHarness();

test("collection members and singular targets are measured in one coherent browser snapshot", () =>
  withPage(
    '<section class="container" style="width:100px;height:100px"><div class="card" style="width:20px;height:20px"></div><div class="card" style="width:20px;height:20px"></div></section>',
    async (page) => {
      const cards = page.locator(".card");
      let resolutions = 0;
      const changingCards = {
        elementHandles: async () => {
          const handles = await cards.elementHandles();
          resolutions += 1;
          if (resolutions === 1) {
            await page.locator(".container").evaluate((container) => {
              container.style.width = "200px";
              for (const card of container.querySelectorAll<HTMLElement>(".card")) {
                card.style.width = "40px";
              }
            });
          }
          return handles;
        },
      } as Locator;
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: changingCards, container: page.locator(".container") },
        }),
        rules: [everyInside(collection("cards"), "container")],
      });
      expectPassed(report);
      expect(resolutions).toBeGreaterThan(1);
    },
  ));

test("a collection snapshot retries when membership changes during capture", () =>
  withPage(
    '<div class="card" style="width:20px;height:20px"></div>',
    async (page) => {
      const cards = page.locator(".card");
      let resolutions = 0;
      const changingCards = {
        elementHandles: async () => {
          const handles = await cards.elementHandles();
          resolutions += 1;
          if (resolutions === 1) {
            await page.evaluate(() => {
              document.body.insertAdjacentHTML(
                "beforeend",
                '<div class="card" style="width:20px;height:20px"></div>',
              );
            });
          }
          return handles;
        },
      } as Locator;
      const report = await checkLayout({
        adapter: playwright(page, {
          targets: { cards: changingCards },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      expectPassed(report);
      expect(resolutions).toBe(3);
    },
  ));

test("an unstable collection snapshot fails instead of mixing member states", () =>
  withPage(
    '<div class="card" style="width:20px;height:20px"></div>',
    async (page) => {
      const cards = page.locator(".card");
      let resolutions = 0;
      const unstableCards = {
        elementHandles: async () => {
          resolutions += 1;
          await page.evaluate(() => {
            document.body.insertAdjacentHTML(
              "beforeend",
              '<div class="card" style="width:20px;height:20px"></div>',
            );
          });
          return cards.elementHandles();
        },
      } as Locator;
      const promise = checkLayout({
        adapter: playwright(page, {
          targets: { cards: unstableCards },
        }),
        rules: [equalWidths(collection("cards"))],
      });
      await expect(promise).rejects.toThrow("stable collection snapshot");
      expect(resolutions).toBeGreaterThan(1);
    },
  ));

test("collection measurement disposes every resolved element handle after success", async () => {
  let disposals = 0;
  const handles = [0, 1, 2].map(() => ({
    dispose: async () => {
      disposals += 1;
    },
  })) as ElementHandle[];
  const cards = {
    elementHandles: async () => handles,
  } as unknown as Locator;
  const page = {
    evaluate: async () => ({
      viewport: { width: 100, height: 100 },
      targets: [{
        target: "cards",
        matches: handles.map(() => ({
          hidden: false,
          rect: { x: 0, y: 0, width: 10, height: 10 },
        })),
      }],
    }),
  } as unknown as Page;
  const report = await checkLayout({
    adapter: playwright(page, { targets: { cards } }),
    rules: [equalWidths(collection("cards"))],
  });
  expect(report.passed).toBe(true);
  expect(disposals).toBe(handles.length);
});

test("collection measurement disposes every resolved element handle after failure", async () => {
  let disposals = 0;
  const handles = [0, 1, 2].map(() => ({
    dispose: async () => {
      disposals += 1;
    },
  })) as ElementHandle[];
  const failure = new Error("browser evaluation failed");
  const cards = {
    elementHandles: async () => handles,
  } as unknown as Locator;
  const page = {
    evaluate: async () => {
      throw failure;
    },
  } as unknown as Page;
  const caught = await checkLayout({
    adapter: playwright(page, { targets: { cards } }),
    rules: [equalWidths(collection("cards"))],
  }).catch((error: unknown) => error);
  expect(caught).toBe(failure);
  expect(disposals).toBe(handles.length);
});
