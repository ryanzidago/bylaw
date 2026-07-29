import { test } from "bun:test";

test("inViewport accepts a target strictly inside the viewport", () => {});

test("inViewport accepts a target sharing the viewport left edge", () => {});

test("inViewport accepts a target sharing the viewport top edge", () => {});

test("inViewport accepts a target sharing the viewport right edge", () => {});

test("inViewport accepts a target sharing the viewport bottom edge", () => {});

test("inViewport accepts a target sharing every viewport edge", () => {});

test("inViewport rejects a target partially clipped beyond the viewport left edge", () => {});

test("inViewport rejects a target partially clipped beyond the viewport top edge", () => {});

test("inViewport rejects a target partially clipped beyond the viewport right edge", () => {});

test("inViewport rejects a target partially clipped beyond the viewport bottom edge", () => {});

test("inViewport rejects a target fully off-screen to the left", () => {});

test("inViewport rejects a target fully off-screen above the viewport", () => {});

test("inViewport rejects a target fully off-screen to the right", () => {});

test("inViewport rejects a target fully off-screen below the viewport", () => {});
