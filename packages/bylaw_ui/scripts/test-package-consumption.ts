import { mkdir, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

async function run(command: string[], cwd: string): Promise<string> {
  const process = Bun.spawn(command, {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error(
      `${command.join(" ")} failed with ${exitCode}\n${stdout}\n${stderr}`,
    );
  }

  return `${stdout}${stderr}`;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

const packageDirectory = process.cwd();
const temporaryDirectory = await mkdtemp(join(tmpdir(), "bylaw-ui-consumer-"));

try {
  await run(
    ["bun", "pm", "pack", "--destination", temporaryDirectory],
    packageDirectory,
  );

  const packedFiles = (await readdir(temporaryDirectory)).filter((file) =>
    file.endsWith(".tgz"),
  );
  assert(packedFiles.length === 1, "pack did not produce exactly one tarball");
  const tarball = join(temporaryDirectory, packedFiles[0]!);
  const contents = await run(["tar", "-tzf", tarball], packageDirectory);
  const entries = contents.trim().split("\n");

  for (const required of [
    "package/dist/index.js",
    "package/dist/index.d.ts",
    "package/dist/playwright.js",
    "package/dist/playwright.d.ts",
    "package/README.md",
    "package/CHANGELOG.md",
    "package/LICENSE",
  ]) {
    assert(entries.includes(required), `packed package is missing ${required}`);
  }

  for (const forbidden of [
    "package/src/",
    "package/test/",
    "package/node_modules/",
    "package/bun.lock",
    "package/tsconfig.json",
  ]) {
    assert(
      !entries.some((entry) => entry.startsWith(forbidden)),
      `packed package contains forbidden ${forbidden}`,
    );
  }

  const consumerDirectory = join(temporaryDirectory, "consumer");
  await mkdir(consumerDirectory);
  await Bun.write(
    join(consumerDirectory, "package.json"),
    JSON.stringify(
      {
        name: "bylaw-ui-isolated-consumer",
        private: true,
        type: "module",
        dependencies: {
          "bylaw-ui": `file:${tarball}`,
          "playwright-core": "1.62.0",
        },
        devDependencies: {
          "@types/node": "26.1.2",
          typescript: "7.0.2",
        },
      },
      null,
      2,
    ),
  );
  await Bun.write(
    join(consumerDirectory, "tsconfig.json"),
    JSON.stringify(
      {
        compilerOptions: {
          lib: ["ESNext", "DOM"],
          module: "NodeNext",
          moduleResolution: "NodeNext",
          outDir: "build",
          strict: true,
          types: ["node"],
        },
        include: ["consumer.ts"],
      },
      null,
      2,
    ),
  );
  await Bun.write(
    join(consumerDirectory, "consumer.ts"),
    `
import { chromium } from "playwright-core";
import { checkLayout, sameSize, type LayoutReport } from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 800, height: 600 } });

try {
  await page.setContent(
    '<div data-testid="a" style="width:10px;height:10px"></div>' +
      '<div data-testid="b" style="width:10px;height:10px"></div>',
  );
  const passing: LayoutReport = await checkLayout({
    adapter: playwright(page),
    rules: [sameSize("a", "b")],
  });
  if (!passing.passed) throw new Error("packed passing check failed");

  await page.locator('[data-testid="b"]').evaluate((element: HTMLElement) => {
    element.style.width = "20px";
  });
  const failing = await checkLayout({
    adapter: playwright(page),
    rules: [sameSize("a", "b")],
  });
  if (failing.passed || failing.findings[0]?.code !== "size-mismatch") {
    throw new Error("packed failing check did not expose size-mismatch");
  }
} finally {
  await browser.close();
}
`,
  );

  await run(["bun", "install"], consumerDirectory);
  await run(["bunx", "tsc"], consumerDirectory);
  await run(["node", "build/consumer.js"], consumerDirectory);

  const installedPackageJson = JSON.parse(
    await readFile(
      join(consumerDirectory, "node_modules/bylaw-ui/package.json"),
      "utf8",
    ),
  ) as { files?: string[] };
  assert(
    installedPackageJson.files?.includes("dist"),
    "installed package metadata is unusable",
  );
  assert(
    (await readdir(join(consumerDirectory, "node_modules/bylaw-ui"))).includes(
      "dist",
    ),
    "installed package has no build output",
  );

  console.log("packed ESM TypeScript consumer passed");
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
