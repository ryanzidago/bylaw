import { test } from "bun:test";

test("passes when every collection member is contained by the target element", () => {});

test("passes when collection members touch the target boundaries", () => {});

test("accepts collection member overflow within the configured tolerance", () => {});

test("accepts collection member overflow equal to the configured tolerance", () => {});

test("fails when collection member overflow exceeds the configured tolerance", () => {});

test("fails when the first collection member overflows the target element", () => {});

test("fails when a middle collection member overflows the target element", () => {});

test("fails when the last collection member overflows the target element", () => {});

test("reports every collection member that overflows the target element", () => {});

test("reports collection member overflow across each target boundary", () => {});

test("requires every collection member to intersect the target even with tolerance", () => {});

test("does not evaluate containment when the singular target is missing", () => {});

test("does not evaluate containment when the singular target has duplicate matches", () => {});
