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
    "CHANGELOG.md",
    "CHEATSHEET.md",
    "README.md",
  ]);
  expect(packageJson).not.toHaveProperty("private");
});

test("the published package includes its changelog", async () => {
  expect(packageJson.files).toContain("CHANGELOG.md");

  const changelog = Bun.file(new URL("../CHANGELOG.md", import.meta.url));
  expect(await changelog.exists()).toBe(true);
  expect(await changelog.text()).toMatch(/^# Changelog\n\n## 0\.1\.0\b/);
});

test("publishing metadata links consumers to package support", () => {
  expect(packageJson).toMatchObject({
    homepage:
      "https://github.com/ryanzidago/bylaw/tree/main/packages/bylaw_ui#readme",
    bugs: {
      url: "https://github.com/ryanzidago/bylaw/issues",
    },
    keywords: expect.arrayContaining([
      "layout-testing",
      "playwright",
      "ui-testing",
    ]),
  });
});

test("the README documents Bun registry installation", async () => {
  const readme = await Bun.file(
    new URL("../README.md", import.meta.url),
  ).text();

  expect(readme).toContain("bun add --dev bylaw-ui @playwright/test");
  expect(readme).not.toMatch(/not published to npm yet/i);
});

test("release instructions require package and consumer verification", async () => {
  const instructions = await Bun.file(
    new URL("../RELEASING.md", import.meta.url),
  ).text();

  expect(instructions).toContain("bun run qa");
  expect(instructions).toContain("bun run test:package");
  expect(instructions).toContain("bun publish --dry-run");
  expect(instructions).toContain("bun publish --access public");
  expect(instructions).toMatch(/install[\s\S]*registry/i);
});
