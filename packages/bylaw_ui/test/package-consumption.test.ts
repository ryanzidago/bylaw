import { expect, test } from "bun:test";

import packageJson from "../package.json";

test("can be imported by an ESM TypeScript consumer", async () => {
  const root = await import("bylaw-ui");
  expect(root.checkLayout).toBeFunction();
  expect(packageJson.type).toBe("module");
});

test("the Playwright entrypoint can be imported independently", async () => {
  const entrypoint = await import("bylaw-ui/playwright");
  expect(entrypoint).toMatchObject({
    playwright: expect.any(Function),
    waitForLayoutTargets: expect.any(Function),
  });
});

test("the published package includes usable JavaScript and type declarations", async () => {
  for (const path of [
    "../dist/index.js",
    "../dist/index.d.ts",
    "../dist/playwright.js",
    "../dist/playwright.d.ts",
  ]) {
    expect(await Bun.file(new URL(path, import.meta.url)).exists()).toBe(true);
  }
});

test("the package declares its supported playwright-core peer dependency", () => {
  expect(packageJson.peerDependencies).toEqual({
    "playwright-core": "^1.62.0",
  });
});

test("publishing metadata uses an explicit file allowlist", () => {
  expect(packageJson.files).toEqual([
    "dist",
    "LICENSE",
    "CHEATSHEET.md",
    "README.md",
  ]);
  expect(packageJson).not.toHaveProperty("private");
});
