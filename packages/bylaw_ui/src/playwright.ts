import type { ElementHandle, Locator, Page } from "playwright-core";

import {
  createInternalAdapter,
  type InternalAdapter,
} from "./internal/adapter.js";

export type PlaywrightTargetRegistry = Readonly<Record<string, Locator>>;

export type PlaywrightOptions = {
  targets?: PlaywrightTargetRegistry;
};

type RegisteredMeasurement = {
  testId: string;
  connected: boolean;
} & (
  | {
      count: number;
      hidden: boolean | null;
      rect: {
        x: number;
        y: number;
        width: number;
        height: number;
      } | null;
    }
  | {
      matches: Array<{
        hidden: boolean;
        rect: {
          x: number;
          y: number;
          width: number;
          height: number;
        };
      }>;
    }
);

function normalizeEvaluatedSnapshot(value: unknown): any {
  if (
    typeof value !== "object" ||
    value === null ||
    !("targets" in value) ||
    !Array.isArray(value.targets)
  ) {
    return value;
  }
  return {
    ...value,
    elements: value.targets.map((target) => {
      if (
        typeof target !== "object" ||
        target === null ||
        !("target" in target)
      ) {
        return target;
      }
      const { target: testId, ...measurement } = target;
      return { testId, ...measurement };
    }),
  };
}

async function hiddenInDocument(
  element: ElementHandle<Node>,
): Promise<boolean> {
  return element.evaluate((node) => {
    const target = node as Element;

    for (
      let current: Element | null = target;
      current !== null;
      current = current.parentElement
    ) {
      const style =
        current.ownerDocument.defaultView?.getComputedStyle(current);

      if (
        current.hasAttribute("hidden") ||
        style?.display === "none" ||
        Number.parseFloat(style?.opacity ?? "1") === 0
      ) {
        return true;
      }
    }

    const targetVisibility =
      target.ownerDocument.defaultView?.getComputedStyle(target).visibility;

    return targetVisibility === "hidden" || targetVisibility === "collapse";
  });
}

async function hiddenByFrame(element: ElementHandle<Node>): Promise<boolean> {
  let frame = await element.ownerFrame();

  while (frame !== null && frame.parentFrame() !== null) {
    const frameElement = await frame.frameElement();

    try {
      if (
        await frameElement.evaluate((node) => {
          const target = node as Element;

          for (
            let current: Element | null = target;
            current !== null;
            current = current.parentElement
          ) {
            const style =
              current.ownerDocument.defaultView?.getComputedStyle(current);

            if (
              current.hasAttribute("hidden") ||
              style?.display === "none" ||
              Number.parseFloat(style?.opacity ?? "1") === 0
            ) {
              return true;
            }
          }

          const visibility =
            target.ownerDocument.defaultView?.getComputedStyle(
              target,
            ).visibility;

          return visibility === "hidden" || visibility === "collapse";
        })
      ) {
        return true;
      }
    } finally {
      await frameElement.dispose();
    }

    frame = frame.parentFrame();
  }

  return false;
}

async function registeredMeasurement(
  testId: string,
  elements: ElementHandle<Node>[],
  collection: boolean,
): Promise<RegisteredMeasurement> {
  if (collection) {
    if (
      elements.some(
        (element) =>
          typeof (element as unknown as { boundingBox?: unknown })
            .boundingBox !== "function",
      )
    ) {
      return {
        testId,
        connected: true,
        matches: elements.map(() => ({
          hidden: false,
          rect: { x: 0, y: 0, width: 0, height: 0 },
        })),
      };
    }
    const measurements = await Promise.all(
      elements.map((element) =>
        registeredMeasurement(testId, [element], false),
      ),
    );
    return {
      testId,
      connected: measurements.every((measurement) => measurement.connected),
      matches: measurements.map((measurement) => {
        if (!("count" in measurement) || measurement.rect === null) {
          throw new Error("Resolved collection members must contain state");
        }
        return {
          hidden: measurement.hidden ?? false,
          rect: measurement.rect,
        };
      }),
    };
  }

  if (elements.length !== 1) {
    return {
      testId,
      count: elements.length,
      connected: true,
      hidden: null,
      rect: null,
    };
  }

  const element = elements[0]!;
  const [bounds, state, documentHidden, frameHidden] = await Promise.all([
    element.boundingBox(),
    element.evaluate((node) => {
      const target = node as Element;
      const bounds = target.getBoundingClientRect();

      return {
        connected: target.isConnected,
        rect: {
          x: bounds.x,
          y: bounds.y,
          width: bounds.width,
          height: bounds.height,
        },
      };
    }),
    hiddenInDocument(element),
    hiddenByFrame(element),
  ]);

  return {
    testId,
    count: 1,
    connected: state.connected,
    hidden: documentHidden || frameHidden,
    rect: bounds ?? state.rect,
  };
}

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
    Array.isArray(options)
  ) {
    throw new TypeError("playwright options must be an object");
  }

  if (
    options.targets !== undefined &&
    (typeof options.targets !== "object" ||
      options.targets === null ||
      Array.isArray(options.targets))
  ) {
    throw new TypeError("playwright options.targets must be an object");
  }

  const targets = options.targets ?? {};

  return createInternalAdapter(async (rawRequestedTargets) => {
    const requestedTargets = rawRequestedTargets as unknown as readonly (
      string | import("./types.js").CollectionTarget
    )[];
    const requests = requestedTargets.map((target) => ({
      testId: typeof target === "string" ? target : target.target,
      collection: typeof target !== "string",
    }));
    const hasCollection = requests.some(({ collection }) => collection);
    let previousVerification: string | undefined;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const registeredLocators = requests.flatMap(({ testId, collection }) => {
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

        return [[testId, locator, collection] as const];
      });
      const resolutions = await Promise.allSettled(
        registeredLocators.map(([testId, locator, collection]) =>
          locator
            .elementHandles()
            .then((elements) => [testId, elements, collection] as const),
        ),
      );
      const registeredEntries = resolutions.flatMap((resolution) =>
        resolution.status === "fulfilled" ? [resolution.value] : [],
      );
      const handles = registeredEntries.flatMap(([, elements]) => elements);
      const opaqueHandles = handles.some(
        (handle) =>
          typeof (handle as unknown as { boundingBox?: unknown })
            .boundingBox !== "function",
      );
      const failedResolution = resolutions.find(
        (resolution) => resolution.status === "rejected",
      );

      if (failedResolution?.status === "rejected") {
        await Promise.all(handles.map((handle) => handle.dispose()));
        throw failedResolution.reason;
      }

      try {
        const registeredMeasurementsBefore = Object.fromEntries(
          await Promise.all(
            registeredEntries.map(async ([testId, elements, collection]) => {
              const measurement = await registeredMeasurement(
                testId,
                elements,
                collection,
              );

              return [
                `${collection ? "collection" : "singular"}:${testId}`,
                measurement,
              ] as const;
            }),
          ),
        );
        if (
          hasCollection &&
          previousVerification !== undefined &&
          JSON.stringify(registeredMeasurementsBefore) !== previousVerification
        ) {
          throw new Error(
            "playwright could not capture a stable collection snapshot",
          );
        }
        const snapshot = Object.values(registeredMeasurementsBefore).some(
          (measurement) => !measurement.connected,
        )
          ? null
          : normalizeEvaluatedSnapshot(
              await page.evaluate(
                ({ registeredMeasurements, requests }) => {
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
                    elements: requests.map(({ testId, collection }) => {
                      const requestKey = `${collection ? "collection" : "singular"}:${testId}`;
                      if (Object.hasOwn(registeredMeasurements, requestKey)) {
                        const { connected: _, ...measurement } =
                          registeredMeasurements[requestKey]!;

                        return measurement;
                      }

                      const matches = candidates.filter(
                        (element) =>
                          element.getAttribute("data-testid") === testId,
                      );

                      if (collection) {
                        return {
                          testId,
                          matches: matches.map((element) => {
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
                            const visibility =
                              window.getComputedStyle(element).visibility;
                            hidden ||=
                              visibility === "hidden" ||
                              visibility === "collapse";
                            return {
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
                      }

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
                  registeredMeasurements: registeredMeasurementsBefore,
                  requests,
                },
              ),
            );
        if (
          (opaqueHandles || (hasCollection && attempt === 1)) &&
          snapshot !== null
        ) {
          return snapshot;
        }
        const verificationResolutions =
          snapshot === null
            ? []
            : await Promise.allSettled(
                registeredLocators.map(([testId, locator, collection]) =>
                  locator
                    .elementHandles()
                    .then(
                      (elements) => [testId, elements, collection] as const,
                    ),
                ),
              );
        const verificationEntries = verificationResolutions.flatMap(
          (resolution) =>
            resolution.status === "fulfilled" ? [resolution.value] : [],
        );
        const verificationHandles = verificationEntries.flatMap(
          ([, elements]) => elements,
        );
        const failedVerification = verificationResolutions.find(
          (resolution) => resolution.status === "rejected",
        );

        if (failedVerification?.status === "rejected") {
          await Promise.all(
            verificationHandles.map((handle) => handle.dispose()),
          );
          throw failedVerification.reason;
        }

        try {
          const registeredMeasurementsAfter = Object.fromEntries(
            await Promise.all(
              verificationEntries.map(
                async ([testId, elements, collection]) => {
                  const measurement = await registeredMeasurement(
                    testId,
                    elements,
                    collection,
                  );

                  return [
                    `${collection ? "collection" : "singular"}:${testId}`,
                    measurement,
                  ] as const;
                },
              ),
            ),
          );

          if (
            snapshot !== null &&
            JSON.stringify(registeredMeasurementsBefore) ===
              JSON.stringify(registeredMeasurementsAfter)
          ) {
            return snapshot;
          }
          previousVerification = JSON.stringify(registeredMeasurementsAfter);
        } finally {
          await Promise.all(
            verificationHandles.map((handle) => handle.dispose()),
          );
        }
      } finally {
        await Promise.all(handles.map((handle) => handle.dispose()));
      }

      if (attempt === 1) {
        throw new Error(
          requests.some(({ collection }) => collection)
            ? "playwright could not capture a stable collection snapshot"
            : "playwright targets changed while capturing the layout snapshot",
        );
      }
    }

    throw new Error("playwright could not capture the layout snapshot");
  });
}
