import { expect, test } from "bun:test";
import type { Page } from "playwright-core";

import {
  checkLayout,
  inViewport,
  sameSize,
  sameWidth,
  width,
  type LayoutRule,
} from "bylaw-ui";
import { playwright, type PlaywrightTargetRegistry } from "bylaw-ui/playwright";
import { browserHarness, expectPassed } from "./logical-target-support";

const withPage = browserHarness();

type ReadinessOptions = {
  timeoutMs: number;
  stableFrames: number;
};

type WaitForLayoutTargets = (
  adapter: ReturnType<typeof playwright>,
  rules: readonly LayoutRule[],
  options: ReadinessOptions,
) => Promise<void>;

async function readinessEntrypoint() {
  return (await import("bylaw-ui/playwright")) as typeof import("bylaw-ui/playwright") & {
    waitForLayoutTargets?: WaitForLayoutTargets;
  };
}

async function waitForLayoutTargets(
  page: Page,
  rules: readonly LayoutRule[],
  options: Partial<ReadinessOptions> = {},
  targets: PlaywrightTargetRegistry = {},
) {
  const entrypoint = await readinessEntrypoint();

  expect(entrypoint.waitForLayoutTargets).toBeFunction();

  return entrypoint.waitForLayoutTargets!(
    playwright(page, { targets }),
    rules,
    {
      timeoutMs: options.timeoutMs ?? 1_000,
      stableFrames: options.stableFrames ?? 2,
    },
  );
}

function readinessError(error: unknown) {
  expect(error).toBeInstanceOf(Error);
  return error as Error & {
    unresolvedTargets?: unknown;
    unstableTargets?: unknown;
    lastObserved?: unknown;
  };
}

test("exports an opt-in Playwright layout readiness helper", async () => {
  const entrypoint = await readinessEntrypoint();

  expect(entrypoint.waitForLayoutTargets).toBeFunction();
  expect(await import("bylaw-ui")).not.toHaveProperty("waitForLayoutTargets");
});

test("waits for a delayed singular layout target to exist", () =>
  withPage(
    '<div data-testid="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        setTimeout(() => {
          document.body.insertAdjacentHTML(
            "beforeend",
            '<div data-testid="subject" style="width:20px;height:20px"></div>',
          );
        }, 100);
      });

      await waitForLayoutTargets(page, [sameSize("subject", "reference")], {
        timeoutMs: 500,
      });

      expectPassed(
        await checkLayout({
          adapter: playwright(page),
          rules: [sameSize("subject", "reference")],
        }),
      );
    },
  ));

test("waits until referenced normalized geometry is stable for the requested animation frames", () =>
  withPage(
    '<div data-testid="subject" style="width:10px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const subject = document.querySelector<HTMLElement>(
          '[data-testid="subject"]',
        )!;
        let frame = 0;

        const move = () => {
          frame += 1;
          subject.style.width = `${10 + frame}px`;

          if (frame < 4) requestAnimationFrame(move);
        };

        requestAnimationFrame(move);
      });

      await waitForLayoutTargets(page, [width("subject", { minPx: 1 })], {
        stableFrames: 3,
      });

      expect(
        await page
          .locator('[data-testid="subject"]')
          .evaluate((element) =>
            Number.parseFloat(getComputedStyle(element).width),
          ),
      ).toBe(14);
    },
  ));

test("requires stable animation frames to be consecutive", () =>
  withPage(
    '<div data-testid="subject" style="width:10px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const subject = document.querySelector<HTMLElement>(
          '[data-testid="subject"]',
        )!;
        const widths = [10, 11, 11, 12, 12, 12];
        let index = 0;

        const advance = () => {
          subject.style.width = `${widths[index]}px`;
          index += 1;

          if (index < widths.length) requestAnimationFrame(advance);
        };

        requestAnimationFrame(advance);
      });

      await waitForLayoutTargets(page, [width("subject", { minPx: 1 })], {
        stableFrames: 3,
      });

      expect(
        await page
          .locator('[data-testid="subject"]')
          .evaluate((element) =>
            Number.parseFloat(getComputedStyle(element).width),
          ),
      ).toBe(12);
    },
  ));

test("starts a new stability streak when relevant geometry changes", () =>
  withPage(
    '<div data-testid="subject" style="width:10px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const subject = document.querySelector<HTMLElement>(
          '[data-testid="subject"]',
        )!;
        let frames = 0;

        const advance = () => {
          frames += 1;

          if (frames === 3) subject.style.width = "30px";
          if (frames < 5) requestAnimationFrame(advance);
        };

        requestAnimationFrame(advance);
      });

      await waitForLayoutTargets(page, [width("subject", { minPx: 1 })], {
        stableFrames: 3,
      });

      expect(
        await page
          .locator('[data-testid="subject"]')
          .evaluate((element) =>
            Number.parseFloat(getComputedStyle(element).width),
          ),
      ).toBe(30);
    },
  ));

test("ignores geometry changes that are not needed by the referenced rules", () =>
  withPage(
    '<div data-testid="subject" style="width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const subject = document.querySelector<HTMLElement>(
          '[data-testid="subject"]',
        )!;

        const move = () => {
          subject.style.left = `${Number.parseFloat(subject.style.left || "0") + 1}px`;
          requestAnimationFrame(move);
        };

        subject.style.position = "absolute";
        requestAnimationFrame(move);
      });

      await waitForLayoutTargets(page, [width("subject", { minPx: 1 })], {
        timeoutMs: 300,
        stableFrames: 3,
      });
    },
  ));

test("ignores unreferenced targets that are missing or continuously moving", () =>
  withPage(
    '<div data-testid="subject" style="width:20px;height:20px"></div><div data-testid="moving" style="position:absolute;width:10px;height:10px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const moving = document.querySelector<HTMLElement>(
          '[data-testid="moving"]',
        )!;

        const move = () => {
          moving.style.left = `${Number.parseFloat(moving.style.left || "0") + 1}px`;
          requestAnimationFrame(move);
        };

        requestAnimationFrame(move);
      });

      await waitForLayoutTargets(
        page,
        [width("subject", { minPx: 1 })],
        { timeoutMs: 300 },
        {
          missing: page.locator(".missing"),
          moving: page.locator('[data-testid="moving"]'),
        },
      );
    },
  ));

test("waits for viewport geometry used by an inViewport rule to stabilize", () =>
  withPage(
    '<div data-testid="subject" style="width:20px;height:20px"></div>',
    async (page) => {
      const resizeViewport = page
        .evaluate(async () => {
          await new Promise<void>((resolve) =>
            requestAnimationFrame(() => resolve()),
          );
        })
        .then(async () => {
          await page.setViewportSize({ width: 700, height: 500 });
          await page.evaluate(
            () =>
              new Promise<void>((resolve) =>
                requestAnimationFrame(() => resolve()),
              ),
          );
          await page.setViewportSize({ width: 600, height: 400 });
        });

      try {
        await waitForLayoutTargets(page, [inViewport("subject")], {
          stableFrames: 3,
        });
      } finally {
        await resizeViewport;
      }

      expect(await page.evaluate(() => [innerWidth, innerHeight])).toEqual([
        600, 400,
      ]);
    },
  ));

test("does not turn stable visibility or zero-size findings into readiness failures", () =>
  withPage(
    '<div data-testid="hidden" hidden style="width:20px;height:20px"></div><div data-testid="zero"></div>',
    async (page) => {
      await waitForLayoutTargets(page, [
        width("hidden", { minPx: 1 }),
        width("zero", { minPx: 1 }),
      ]);

      const report = await checkLayout({
        adapter: playwright(page),
        rules: [width("hidden", { minPx: 1 }), width("zero", { minPx: 1 })],
      });

      expect(report.findings.map(({ category }) => category)).toEqual([
        "element-visibility",
        "element-visibility",
      ]);
    },
  ));

test("times out when referenced geometry never stabilizes", () =>
  withPage(
    '<div data-testid="subject" style="position:absolute;width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const subject = document.querySelector<HTMLElement>(
          '[data-testid="subject"]',
        )!;

        const move = () => {
          subject.style.width = `${Number.parseFloat(subject.style.width) + 1}px`;
          requestAnimationFrame(move);
        };

        requestAnimationFrame(move);
      });

      try {
        await waitForLayoutTargets(page, [width("subject", { minPx: 1 })], {
          timeoutMs: 100,
          stableFrames: 3,
        });
        throw new Error("expected readiness to time out");
      } catch (error) {
        expect(readinessError(error).name).toBe("LayoutReadinessTimeoutError");
      }
    },
  ));

test("times out when a referenced target remains missing", () =>
  withPage("", async (page) => {
    try {
      await waitForLayoutTargets(page, [width("missing", { minPx: 1 })], {
        timeoutMs: 100,
      });
      throw new Error("expected readiness to time out");
    } catch (error) {
      expect(readinessError(error).name).toBe("LayoutReadinessTimeoutError");
    }
  }));

test("identifies unresolved and unstable targets in timeout errors", () =>
  withPage(
    '<div data-testid="unstable" style="width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const unstable = document.querySelector<HTMLElement>(
          '[data-testid="unstable"]',
        )!;

        const resize = () => {
          unstable.style.width = `${Number.parseFloat(unstable.style.width) + 1}px`;
          requestAnimationFrame(resize);
        };

        requestAnimationFrame(resize);
      });

      try {
        await waitForLayoutTargets(page, [sameWidth("missing", "unstable")], {
          timeoutMs: 100,
          stableFrames: 3,
        });
        throw new Error("expected readiness to time out");
      } catch (error) {
        const timeout = readinessError(error);
        expect(timeout.message).toContain("missing");
        expect(timeout.message).toContain("unstable");
        expect(timeout.unresolvedTargets).toContain("missing");
        expect(timeout.unstableTargets).toContain("unstable");
      }
    },
  ));

test("includes each target's last observed resolution and geometry state in timeout errors", () =>
  withPage(
    '<div data-testid="unstable" style="position:absolute;left:12px;top:34px;width:56px;height:78px"></div>',
    async (page) => {
      await page.evaluate(() => {
        const unstable = document.querySelector<HTMLElement>(
          '[data-testid="unstable"]',
        )!;

        const resize = () => {
          unstable.style.width = `${Number.parseFloat(unstable.style.width) + 1}px`;
          requestAnimationFrame(resize);
        };

        requestAnimationFrame(resize);
      });

      try {
        await waitForLayoutTargets(page, [sameSize("missing", "unstable")], {
          timeoutMs: 100,
          stableFrames: 3,
        });
        throw new Error("expected readiness to time out");
      } catch (error) {
        const timeout = readinessError(error);
        expect(timeout.lastObserved).toMatchObject({
          missing: { matchCount: 0 },
          unstable: {
            matchCount: 1,
            geometry: {
              x: 12,
              y: 34,
              height: 78,
            },
          },
        });
      }
    },
  ));

test("does not choose a fallback match for missing or duplicate singular targets", () =>
  withPage(
    '<div data-testid="missing" style="width:20px;height:20px"></div><div data-testid="duplicate" style="width:20px;height:20px"></div>',
    async (page) => {
      const targets = {
        missing: page.locator(".absent"),
        duplicate: page.locator("div"),
      };

      try {
        await waitForLayoutTargets(
          page,
          [sameSize("missing", "duplicate")],
          { timeoutMs: 100 },
          targets,
        );
        throw new Error("expected readiness to time out");
      } catch (error) {
        const timeout = readinessError(error);
        expect(timeout.name).toBe("LayoutReadinessTimeoutError");
        expect(timeout.lastObserved).toMatchObject({
          missing: { matchCount: 0 },
          duplicate: { matchCount: 2 },
        });
      }
    },
  ));

test("waits for a duplicate singular target to resolve to exactly one match", () =>
  withPage(
    '<div class="candidate" style="width:20px;height:20px"></div><div class="candidate" style="width:20px;height:20px"></div><div class="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        setTimeout(() => document.querySelector(".candidate")?.remove(), 100);
      });

      await waitForLayoutTargets(
        page,
        [sameSize("candidate", "reference")],
        { timeoutMs: 500 },
        {
          candidate: page.locator(".candidate"),
          reference: page.locator(".reference"),
        },
      );

      expect(await page.locator(".candidate").count()).toBe(1);
    },
  ));

test("reports a still-duplicate singular target as unresolved at timeout", () =>
  withPage(
    '<div class="candidate"></div><div class="candidate"></div>',
    async (page) => {
      try {
        await waitForLayoutTargets(
          page,
          [width("candidate", { minPx: 1 })],
          { timeoutMs: 100 },
          { candidate: page.locator(".candidate") },
        );
        throw new Error("expected readiness to time out");
      } catch (error) {
        const timeout = readinessError(error);
        expect(timeout.message).toContain("candidate");
        expect(timeout.lastObserved).toMatchObject({
          candidate: { matchCount: 2 },
        });
      }
    },
  ));

test("honors the caller-defined timeout", () =>
  withPage("", async (page) => {
    const startedAt = performance.now();

    await expect(
      waitForLayoutTargets(page, [width("missing", { minPx: 1 })], {
        timeoutMs: 80,
      }),
    ).rejects.toThrow();

    const elapsedMs = performance.now() - startedAt;
    expect(elapsedMs).toBeGreaterThanOrEqual(60);
    expect(elapsedMs).toBeLessThan(300);
  }));

test("waits for every member of a referenced collection to exist and stabilize", () =>
  withPage(
    '<div class="member" style="width:20px;height:20px"></div>',
    async (page) => {
      const collectionRule = {
        kind: "collectionEqualWidth",
        collection: "members",
      } as unknown as LayoutRule;

      await page.evaluate(() => {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            document.body.insertAdjacentHTML(
              "beforeend",
              '<div class="member" style="width:20px;height:20px"></div>',
            );
          });
        });
      });

      await waitForLayoutTargets(
        page,
        [collectionRule],
        { timeoutMs: 500 },
        {
          members: page.locator(".member"),
        },
      );

      expect(await page.locator(".member").count()).toBe(2);
    },
  ));

test("restarts collection stability when membership changes", () =>
  withPage(
    '<div class="member" data-member="first" style="width:20px;height:20px"></div>',
    async (page) => {
      const collectionRule = {
        kind: "collectionEqualWidth",
        collection: "members",
      } as unknown as LayoutRule;

      await page.evaluate(() => {
        let frames = 0;

        const changeMembership = () => {
          frames += 1;

          if (frames === 3) {
            document.querySelector(".member")?.remove();
            document.body.insertAdjacentHTML(
              "beforeend",
              '<div class="member" data-member="replacement" style="width:20px;height:20px"></div>',
            );
          }

          if (frames < 5) requestAnimationFrame(changeMembership);
        };

        requestAnimationFrame(changeMembership);
      });

      await waitForLayoutTargets(
        page,
        [collectionRule],
        { stableFrames: 3 },
        { members: page.locator(".member") },
      );

      expect(await page.locator(".member").getAttribute("data-member")).toBe(
        "replacement",
      );
    },
  ));

test("reports unresolved and unstable members of the same collection independently", () =>
  withPage(
    '<div class="member" data-member="stable" style="width:20px;height:20px"></div><div class="member" data-member="unstable" style="width:20px;height:20px"></div>',
    async (page) => {
      const collectionRule = {
        kind: "collectionEqualWidth",
        collection: "members",
      } as unknown as LayoutRule;

      await page.evaluate(() => {
        const unstable = document.querySelector<HTMLElement>(
          '[data-member="unstable"]',
        )!;

        const resize = () => {
          unstable.style.width = `${Number.parseFloat(unstable.style.width) + 1}px`;
          requestAnimationFrame(resize);
        };

        requestAnimationFrame(resize);
        setTimeout(
          () => document.querySelector('[data-member="stable"]')?.remove(),
          50,
        );
      });

      try {
        await waitForLayoutTargets(
          page,
          [collectionRule],
          { timeoutMs: 100, stableFrames: 3 },
          { members: page.locator(".member") },
        );
        throw new Error("expected readiness to time out");
      } catch (error) {
        const timeout = readinessError(error);
        expect(timeout.message).toContain("members[0]");
        expect(timeout.message).toContain("members[1]");
        expect(timeout.unresolvedTargets).toContain("members[0]");
        expect(timeout.unstableTargets).toContain("members[1]");
      }
    },
  ));

test("leaves checkLayout as an immediate single-snapshot operation", () =>
  withPage(
    '<div data-testid="reference" style="width:20px;height:20px"></div>',
    async (page) => {
      await page.evaluate(() => {
        setTimeout(() => {
          document.body.insertAdjacentHTML(
            "beforeend",
            '<div data-testid="subject" style="width:20px;height:20px"></div>',
          );
        }, 250);
      });
      const startedAt = performance.now();
      const report = await checkLayout({
        adapter: playwright(page),
        rules: [sameSize("subject", "reference")],
      });

      expect(performance.now() - startedAt).toBeLessThan(200);
      expect(report.findings[0]).toMatchObject({
        category: "element-resolution",
        code: "missing-element",
        testId: "subject",
      });
    },
  ));

test("documents readiness before checkLayout as an explicit opt-in sequence", async () => {
  const readme = await Bun.file(
    new URL("../../README.md", import.meta.url),
  ).text();
  const readinessCall = readme.indexOf("waitForLayoutTargets(");
  const checkCall = readme.indexOf("checkLayout(", readinessCall);

  expect(readinessCall).toBeGreaterThan(-1);
  expect(checkCall).toBeGreaterThan(readinessCall);
  expect(readme).toContain("readiness");
  expect(readme).toContain("assertion");
});
