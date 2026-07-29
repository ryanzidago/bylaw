import { test } from "bun:test";

test("passes when no collection members overlap", () => {});

test("passes when collection members only touch at their boundaries", () => {});

test("passes when a collection contains one member", () => {});

test("fails when two adjacent collection members overlap", () => {});

test("fails when two non-adjacent collection members overlap", () => {});

test("reports every overlapping pair in the collection", () => {});

test("does not report the same overlapping pair twice", () => {});
