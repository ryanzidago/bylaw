import { test } from "bun:test";

test(
  "reports alignment coordinates difference tolerance and excess",
  () => {},
);

test(
  "reports ordering gap boundary crossing tolerance and excess",
  () => {},
);

test("reports a measured gap below its allowed range", () => {});

test("reports a measured gap above its allowed range", () => {});

test("reports missing overlap geometry", () => {});

test("reports overlap below its allowed range", () => {});

test("reports overlap above its allowed range", () => {});

test("reports unexpected overlap geometry", () => {});

test("reports containment overflow tolerance and excess", () => {});

test("reports geometry for disjoint containment", () => {});

test(
  "reports width measurements difference tolerance and excess",
  () => {},
);

test(
  "reports height measurements difference tolerance and excess",
  () => {},
);

test("reports both dimensions for a size mismatch", () => {});
