import { expect, test } from "bun:test";

const readme = await Bun.file(new URL("../README.md", import.meta.url)).text();

function customAdapterSection(): string {
  const match = readme.match(
    /## (?:Custom|Public) adapter\b([\s\S]*?)(?=\n## |\s*$)/i,
  );
  expect(match).not.toBeNull();
  return match?.[0] ?? "";
}

test("the README documents the public custom adapter compatibility contract", () => {
  const section = customAdapterSection();
  expect(section).toContain("createAdapter");
  expect(section).toMatch(/normalized/i);
});

test("the README includes a small non-Playwright adapter example", () => {
  const section = customAdapterSection();
  expect(section).toMatch(
    /```ts[\s\S]*createAdapter\([\s\S]*measure[\s\S]*```/,
  );
  expect(section).not.toMatch(/```ts[\s\S]*from "bylaw-ui\/playwright"/);
});

test("the README non-Playwright example uses only supported package exports", () => {
  const section = customAdapterSection();
  const example = section.match(/```ts\n([\s\S]*?)```/)?.[1] ?? "";
  expect(example).toMatch(/from "bylaw-ui"/);
  expect(example).not.toMatch(/src\/|internal\/|bylaw-ui\/playwright/);
});

test("the README states the normalized rectangle coordinate system", () => {
  expect(customAdapterSection()).toMatch(
    /viewport-relative[\s\S]*axis-aligned[\s\S]*border-box[\s\S]*fractional CSS pixels/i,
  );
});

test("the README documents missing ambiguous and collection target results", () => {
  const section = customAdapterSection();
  expect(section).toMatch(/missing/i);
  expect(section).toMatch(/ambiguous/i);
  expect(section).toMatch(/collection/i);
});

test("the README documents how adapter measurement failures propagate", () => {
  expect(customAdapterSection()).toMatch(
    /(?:throws|rejections|failures)[\s\S]*(?:propagate|preserved)/i,
  );
});

test("the README distinguishes malformed measurements from layout findings", () => {
  expect(customAdapterSection()).toMatch(
    /malformed[\s\S]*(?:validation error|MeasurementValidationError)[\s\S]*(?:finding|report)/i,
  );
});

test("the README keeps target discovery and platform waiting outside the geometry engine", () => {
  const section = customAdapterSection();
  expect(section).toMatch(/target discovery/i);
  expect(section).toMatch(
    /(?:waiting|waits)[\s\S]*(?:adapter|platform|consumer)/i,
  );
});

test("the README does not assign relationship inference or aesthetic evaluation to adapters", () => {
  const section = customAdapterSection();
  expect(section).toMatch(/relationship inference/i);
  expect(section).toMatch(/aesthetic evaluation/i);
  expect(section).toMatch(/(?:does not|outside|not responsible)/i);
});
