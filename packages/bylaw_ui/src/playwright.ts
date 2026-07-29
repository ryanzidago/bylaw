import type { Locator, Page } from "playwright-core";

import {
  createInternalAdapter,
  type InternalAdapter,
} from "./internal/adapter.js";

export type PlaywrightTargetRegistry = Readonly<Record<string, Locator>>;

export type PlaywrightOptions = {
  targets?: PlaywrightTargetRegistry;
};

export function playwright(
  page: Page,
  options: PlaywrightOptions = {},
): InternalAdapter {
  if (
    typeof page !== "object" ||
    page === null ||
    typeof page.evaluate !== "function"
  ) {
    throw new TypeError("playwright expects a playwright-core Page");
  }

  if (
    typeof options !== "object" ||
    options === null ||
    (options.targets !== undefined &&
      (typeof options.targets !== "object" || options.targets === null))
  ) {
    throw new TypeError("playwright options.targets must be an object");
  }

  const targets = options.targets ?? {};

  return createInternalAdapter(async (testIds) => {
    const registeredEntries = await Promise.all(
      testIds.flatMap((testId) => {
        if (!Object.hasOwn(targets, testId)) {
          return [];
        }

        const locator = targets[testId];

        if (
          typeof locator !== "object" ||
          locator === null ||
          typeof locator.elementHandles !== "function"
        ) {
          throw new TypeError(
            `playwright target "${testId}" must be a playwright-core Locator`,
          );
        }

        return [
          locator
            .elementHandles()
            .then((elements) => [testId, elements] as const),
        ];
      }),
    );
    const registeredTargets = Object.fromEntries(registeredEntries);
    const handles = registeredEntries.flatMap(([, elements]) => elements);

    try {
      return await page.evaluate(
        ({ requestedTestIds, registeredTargets }) => {
          const candidates = Array.from(
            document.querySelectorAll<HTMLElement | SVGElement>(
              "[data-testid]",
            ),
          );

          return {
            viewport: {
              width: window.innerWidth,
              height: window.innerHeight,
            },
            elements: requestedTestIds.map((testId) => {
              const matches = (
                Object.hasOwn(registeredTargets, testId)
                  ? registeredTargets[testId]!
                  : candidates.filter(
                      (element) =>
                        element.getAttribute("data-testid") === testId,
                    )
              ) as Element[];

              if (matches.length !== 1) {
                return {
                  testId,
                  count: matches.length,
                  hidden: null,
                  rect: null,
                };
              }

              const element = matches[0]!;
              const bounds = element.getBoundingClientRect();
              let hidden = false;

              for (
                let current: Element | null = element;
                current !== null;
                current = current.parentElement
              ) {
                const style = window.getComputedStyle(current);

                if (
                  current.hasAttribute("hidden") ||
                  style.display === "none" ||
                  Number.parseFloat(style.opacity) === 0
                ) {
                  hidden = true;
                  break;
                }
              }

              const targetVisibility =
                window.getComputedStyle(element).visibility;

              if (
                targetVisibility === "hidden" ||
                targetVisibility === "collapse"
              ) {
                hidden = true;
              }

              return {
                testId,
                count: 1,
                hidden,
                rect: {
                  x: bounds.x,
                  y: bounds.y,
                  width: bounds.width,
                  height: bounds.height,
                },
              };
            }),
          };
        },
        {
          requestedTestIds: [...testIds],
          registeredTargets,
        },
      );
    } finally {
      await Promise.all(handles.map((handle) => handle.dispose()));
    }
  });
}
