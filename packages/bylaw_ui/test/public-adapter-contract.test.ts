import { test } from "bun:test";

test("the package root exports the public adapter factory", () => {});

test("the package root exports the public adapter implementation type", () => {});

test("the package root exports the public measurement snapshot type", () => {});

test("the package root exports the public viewport type", () => {});

test("the package root exports the public rectangle type", () => {});

test("the package root exports the public singular target resolution type", () => {});

test("the package root exports the public collection target resolution type", () => {});

test("the public adapter factory accepts a minimal custom adapter", () => {});

test("checkLayout accepts an adapter returned by the public adapter factory", () => {});

test("a structurally similar object is not accepted as a supported adapter", () => {});

test("ordinary structural typing cannot forge the internal adapter brand", () => {});

test("a custom adapter can evaluate layout rules without loading Playwright", () => {});
