import type { Page } from "playwright-core";

import {
  createInternalAdapter,
  type InternalAdapter,
} from "./internal/adapter";

export function playwright(page: Page): InternalAdapter {
  if (
    typeof page !== "object" ||
    page === null ||
    typeof page.evaluate !== "function"
  ) {
    throw new TypeError("playwright expects a playwright-core Page");
  }

  return createInternalAdapter((testIds) =>
    page.evaluate((requestedTestIds) => {
      const candidates = Array.from(
        document.querySelectorAll<HTMLElement | SVGElement>("[data-testid]"),
      );

      return {
        viewport: {
          width: window.innerWidth,
          height: window.innerHeight,
        },
        elements: requestedTestIds.map((testId) => {
          const matches = candidates.filter(
            (element) => element.getAttribute("data-testid") === testId,
          );

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

          const targetVisibility = window.getComputedStyle(element).visibility;

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
    }, [...testIds]),
  );
}
