import type { ElementHandle, Locator, Page } from "playwright-core";

import {
  createInternalAdapter,
  type InternalAdapter,
  type RawElementMeasurement,
  type RawMeasurementSnapshot,
} from "./internal/adapter.js";
import type { LayoutRule } from "./types.js";

export type PlaywrightTargetRegistry = Readonly<Record<string, Locator>>;

export type PlaywrightOptions = {
  targets?: PlaywrightTargetRegistry;
};

export type LayoutReadinessOptions = {
  timeoutMs: number;
  stableFrames: number;
};

export type LayoutReadinessObservation = {
  matchCount: number;
  geometry?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
};

export class LayoutReadinessTimeoutError extends Error {
  readonly unresolvedTargets: string[];
  readonly unstableTargets: string[];
  readonly lastObserved: Readonly<Record<string, LayoutReadinessObservation>>;

  constructor(
    unresolvedTargets: string[],
    unstableTargets: string[],
    lastObserved: Readonly<Record<string, LayoutReadinessObservation>>,
  ) {
    const details = [
      unresolvedTargets.length > 0
        ? `unresolved targets: ${unresolvedTargets.join(", ")}`
        : null,
      unstableTargets.length > 0
        ? `unstable targets: ${unstableTargets.join(", ")}`
        : null,
    ].filter((detail): detail is string => detail !== null);

    super(`Layout readiness timed out (${details.join("; ")})`);
    this.name = "LayoutReadinessTimeoutError";
    this.unresolvedTargets = unresolvedTargets;
    this.unstableTargets = unstableTargets;
    this.lastObserved = lastObserved;
  }
}

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

type PlaywrightAdapterMetadata = {
  page: Page;
  targets: PlaywrightTargetRegistry;
};

const adapterMetadata = new WeakMap<
  InternalAdapter,
  PlaywrightAdapterMetadata
>();

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

  const adapter = createInternalAdapter(async (rawRequestedTargets) => {
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

  adapterMetadata.set(adapter, { page, targets });
  return adapter;
}

type GeometryField = "x" | "y" | "width" | "height";

type TargetRequirement = {
  fields: Set<GeometryField>;
  viewport: boolean;
};

type CollectionMemberMeasurement = {
  identity: number;
  rect: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
};

type StabilityState = {
  signature: string | null;
  stableFrames: number;
};

function addRequirement(
  requirements: Map<string, TargetRequirement>,
  testId: string,
  fields: readonly GeometryField[],
  viewport = false,
) {
  const requirement = requirements.get(testId) ?? {
    fields: new Set<GeometryField>(),
    viewport: false,
  };

  fields.forEach((field) => requirement.fields.add(field));
  requirement.viewport ||= viewport;
  requirements.set(testId, requirement);
}

function alignmentFields(
  alignment: Extract<LayoutRule, { kind: "align" }>["alignment"],
): readonly GeometryField[] {
  switch (alignment) {
    case "left":
      return ["x"];
    case "right":
    case "centerX":
      return ["x", "width"];
    case "top":
      return ["y"];
    case "bottom":
    case "centerY":
      return ["y", "height"];
  }
}

function referencedTargets(rules: readonly LayoutRule[]) {
  const requirements = new Map<string, TargetRequirement>();
  const collections = new Map<string, Set<GeometryField>>();

  for (const rule of rules) {
    switch (rule.kind) {
      case "equalWidths":
        collections.set(rule.collection.target, new Set(["width"]));
        break;
      case "verticallyOrdered":
        collections.set(rule.collection.target, new Set(["y", "height"]));
        break;
      case "pairwiseNotOverlap":
        collections.set(
          rule.collection.target,
          new Set(["x", "y", "width", "height"]),
        );
        break;
      case "everyInside":
        collections.set(
          rule.collection.target,
          new Set(["x", "y", "width", "height"]),
        );
        addRequirement(requirements, rule.container, [
          "x",
          "y",
          "width",
          "height",
        ]);
        break;
      case "width":
        addRequirement(requirements, rule.target, ["width"]);
        break;
      case "height":
        addRequirement(requirements, rule.target, ["height"]);
        break;
      case "inViewport":
        addRequirement(
          requirements,
          rule.target,
          ["x", "y", "width", "height"],
          true,
        );
        break;
      case "sameWidth":
        addRequirement(requirements, rule.subject, ["width"]);
        addRequirement(requirements, rule.reference, ["width"]);
        break;
      case "sameHeight":
        addRequirement(requirements, rule.subject, ["height"]);
        addRequirement(requirements, rule.reference, ["height"]);
        break;
      case "sameSize":
        addRequirement(requirements, rule.subject, ["width", "height"]);
        addRequirement(requirements, rule.reference, ["width", "height"]);
        break;
      case "align": {
        const fields = alignmentFields(rule.alignment);
        addRequirement(requirements, rule.subject, fields);
        addRequirement(requirements, rule.reference, fields);
        break;
      }
      case "above":
      case "below":
        addRequirement(requirements, rule.subject, ["y", "height"]);
        addRequirement(requirements, rule.reference, ["y", "height"]);
        break;
      case "leftOf":
      case "rightOf":
        addRequirement(requirements, rule.subject, ["x", "width"]);
        addRequirement(requirements, rule.reference, ["x", "width"]);
        break;
      default:
        addRequirement(requirements, rule.subject, [
          "x",
          "y",
          "width",
          "height",
        ]);
        addRequirement(requirements, rule.reference, [
          "x",
          "y",
          "width",
          "height",
        ]);
    }
  }

  return { requirements, collections };
}

function assertReadinessOptions(
  options: LayoutReadinessOptions,
): asserts options is LayoutReadinessOptions {
  if (
    typeof options !== "object" ||
    options === null ||
    Array.isArray(options)
  ) {
    throw new TypeError("layout readiness options must be an object");
  }

  if (!Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new TypeError("layout readiness timeoutMs must be a positive number");
  }

  if (!Number.isInteger(options.stableFrames) || options.stableFrames <= 0) {
    throw new TypeError(
      "layout readiness stableFrames must be a positive integer",
    );
  }
}

function measurementSignature(
  measurement: RawElementMeasurement,
  requirement: TargetRequirement,
  viewport: RawMeasurementSnapshot["viewport"],
) {
  if (measurement.count !== 1 || measurement.rect === null) {
    return null;
  }

  const geometry = Object.fromEntries(
    [...requirement.fields].map((field) => [field, measurement.rect![field]]),
  );

  return JSON.stringify(
    requirement.viewport ? { geometry, viewport } : { geometry },
  );
}

function updateStability(state: StabilityState, signature: string | null) {
  if (signature === null) {
    state.signature = null;
    state.stableFrames = 0;
  } else if (signature === state.signature) {
    state.stableFrames += 1;
  } else {
    state.signature = signature;
    state.stableFrames = 0;
  }
}

async function animationFrame(page: Page) {
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        requestAnimationFrame(() => resolve());
      }),
  );
}

async function collectionMeasurements(
  locator: Locator,
): Promise<CollectionMemberMeasurement[]> {
  const handles = await locator.elementHandles();

  try {
    return await Promise.all(
      handles.map((handle) =>
        handle.evaluate((node) => {
          const scope = globalThis as typeof globalThis & {
            __bylawLayoutReadinessIdentities?: WeakMap<object, number>;
            __bylawLayoutReadinessNextIdentity?: number;
          };
          const identities =
            scope.__bylawLayoutReadinessIdentities ??
            (scope.__bylawLayoutReadinessIdentities = new WeakMap());
          let identity = identities.get(node);

          if (identity === undefined) {
            identity = scope.__bylawLayoutReadinessNextIdentity ?? 0;
            scope.__bylawLayoutReadinessNextIdentity = identity + 1;
            identities.set(node, identity);
          }

          const bounds = (node as Element).getBoundingClientRect();

          return {
            identity,
            rect: {
              x: bounds.x,
              y: bounds.y,
              width: bounds.width,
              height: bounds.height,
            },
          };
        }),
      ),
    );
  } finally {
    await Promise.all(handles.map((handle) => handle.dispose()));
  }
}

/**
 * Waits until targets referenced by layout rules resolve and retain the
 * rule-relevant geometry for consecutive animation frames.
 */
export async function waitForLayoutTargets(
  adapter: InternalAdapter,
  rules: readonly LayoutRule[],
  options: LayoutReadinessOptions,
): Promise<void> {
  const metadata = adapterMetadata.get(adapter);

  if (metadata === undefined) {
    throw new TypeError(
      "waitForLayoutTargets expects an adapter created by playwright",
    );
  }

  if (!Array.isArray(rules)) {
    throw new TypeError("waitForLayoutTargets rules must be an array");
  }

  assertReadinessOptions(options);

  const { requirements, collections } = referencedTargets(rules);
  const targetStates = new Map(
    [...requirements].map(([testId]) => [
      testId,
      { signature: null, stableFrames: 0 } satisfies StabilityState,
    ]),
  );
  const collectionStates = new Map<
    string,
    {
      membership: string | null;
      members: Map<number, StabilityState & { label: string }>;
      history: Map<
        number,
        { label: string; observation: LayoutReadinessObservation }
      >;
      nextLabel: number;
    }
  >();
  const lastObserved: Record<string, LayoutReadinessObservation> = {};
  const startedAt = performance.now();

  for (const [collection] of collections) {
    collectionStates.set(collection, {
      membership: null,
      members: new Map(),
      history: new Map(),
      nextLabel: 0,
    });
  }

  while (true) {
    await animationFrame(metadata.page);

    const testIds = [...requirements.keys()];
    const snapshot = (await adapter.measure(testIds)) as RawMeasurementSnapshot;

    for (const measurement of snapshot.elements) {
      const requirement = requirements.get(measurement.testId)!;
      const state = targetStates.get(measurement.testId)!;

      updateStability(
        state,
        measurementSignature(measurement, requirement, snapshot.viewport),
      );
      lastObserved[measurement.testId] = {
        matchCount: measurement.count,
        ...(measurement.rect === null
          ? {}
          : { geometry: { ...measurement.rect } }),
      };
    }

    for (const [collection, fields] of collections) {
      const locator = metadata.targets[collection];

      if (locator === undefined) {
        throw new TypeError(
          `collection target "${collection}" must be a registered Playwright locator`,
        );
      }

      const measurements = await collectionMeasurements(locator);
      const state = collectionStates.get(collection)!;
      const membership = measurements
        .map((measurement) => measurement.identity)
        .sort((left, right) => left - right)
        .join(",");
      const membershipChanged =
        state.membership !== null && membership !== state.membership;
      const currentIdentities = new Set(
        measurements.map((measurement) => measurement.identity),
      );

      if (measurements.length === 0) {
        lastObserved[collection] = { matchCount: 0 };
      } else {
        delete lastObserved[collection];
      }

      for (const [identity, member] of state.members) {
        if (!currentIdentities.has(identity)) {
          state.history.set(identity, {
            label: member.label,
            observation: { matchCount: 0 },
          });
          state.members.delete(identity);
        }
      }

      for (const measurement of measurements) {
        let member = state.members.get(measurement.identity);

        if (member === undefined) {
          member = {
            label: `${collection}[${state.nextLabel}]`,
            signature: null,
            stableFrames: 0,
          };
          state.nextLabel += 1;
          state.members.set(measurement.identity, member);
        }

        const geometry = Object.fromEntries(
          [...fields].map((field) => [field, measurement.rect[field]]),
        );

        if (membershipChanged) {
          member.signature = null;
          member.stableFrames = 0;
        }

        updateStability(member, JSON.stringify(geometry));
        const observation = {
          matchCount: 1,
          geometry: { ...measurement.rect },
        };
        lastObserved[member.label] = observation;
        state.history.set(measurement.identity, {
          label: member.label,
          observation,
        });
      }

      state.membership = membership;
    }

    const targetsReady = [...targetStates.values()].every(
      (state) => state.stableFrames >= options.stableFrames,
    );
    const collectionsReady = [...collectionStates.values()].every(
      (state) =>
        state.members.size > 0 &&
        [...state.members.values()].every(
          (member) => member.stableFrames >= options.stableFrames,
        ),
    );

    if (targetsReady && collectionsReady) {
      return;
    }

    if (performance.now() - startedAt >= options.timeoutMs) {
      const unresolvedTargets = [...targetStates]
        .filter(([, state]) => state.signature === null)
        .map(([testId]) => testId);
      const unstableTargets = [...targetStates]
        .filter(
          ([, state]) =>
            state.signature !== null &&
            state.stableFrames < options.stableFrames,
        )
        .map(([testId]) => testId);

      for (const [collection, state] of collectionStates) {
        if (state.members.size === 0) {
          unresolvedTargets.push(collection);
        }

        for (const { label, observation } of state.history.values()) {
          lastObserved[label] = observation;

          if (observation.matchCount === 0) {
            unresolvedTargets.push(label);
          }
        }

        for (const member of state.members.values()) {
          if (member.stableFrames < options.stableFrames) {
            unstableTargets.push(member.label);
          }
        }
      }

      throw new LayoutReadinessTimeoutError(
        unresolvedTargets,
        unstableTargets,
        lastObserved,
      );
    }
  }
}
