import { expect, test } from "bun:test";

import * as bylawUi from "bylaw-ui";

test("imports the package root", () => {
  expect(bylawUi).toBeDefined();
});
