import { test } from "bun:test";

test("passes when collection members are vertically ordered", () => {});

test("passes when every adjacent gap is inside the allowed range", () => {});

test("passes when adjacent gaps equal the allowed range boundaries", () => {});

test("passes when a collection contains one member", () => {});

test("fails when two adjacent collection members are out of vertical order", () => {});

test("fails when an adjacent gap is smaller than the allowed minimum", () => {});

test("fails when an adjacent gap is larger than the allowed maximum", () => {});

test("reports every adjacent pair whose vertical ordering fails", () => {});

test("reports every adjacent pair whose gap is outside the allowed range", () => {});

test("preserves fractional gaps between collection members", () => {});
