import { expect, test } from "bun:test";

test("the README documents explicit collection targeting separately from singular targeting", async () => {
  const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();
  expect(readme).toContain("Collection targets");
  expect(readme).toContain("Singular targets");
});

test("the README documents that an empty collection reports resolution failure and skips geometry", async () => {
  const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();
  expect(readme).toMatch(/empty collection[\s\S]*resolution/i);
  expect(readme).toMatch(/empty collection[\s\S]*skip(?:s|ped)? geometry/i);
});

test("the README shows representative containment equal-width vertical-ordering and non-overlap collection rules", async () => {
  const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();
  expect(readme).toContain("everyInside(");
  expect(readme).toContain("equalWidths(");
  expect(readme).toContain("verticallyOrdered(");
  expect(readme).toContain("pairwiseNotOverlap(");
});

test("the README documents how target order determines collection evaluation and reporting order", async () => {
  const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();
  expect(readme).toMatch(/target order[\s\S]*evaluation order/i);
  expect(readme).toMatch(/target order[\s\S]*reporting order/i);
});

test("the README states that duplicate singular targets remain errors", async () => {
  const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();
  expect(readme).toMatch(/singular target[\s\S]*multiple match(?:es)?[\s\S]*error/i);
});
