import { test } from "bun:test";

test("the public adapter factory rejects a missing implementation", () => {});

test("the public adapter factory rejects null", () => {});

test("the public adapter factory rejects an array", () => {});

test("the public adapter factory rejects an implementation without measure", () => {});

test("the public adapter factory rejects a nonfunction measure property", () => {});

test("the public adapter factory reports the invalid measure property in its error", () => {});

test("the public adapter factory does not invoke measure during construction", () => {});

test("a factory-created adapter invokes the consumer measure function", () => {});

test("a factory-created adapter passes every unique referenced target to measure", () => {});

test("a factory-created adapter invokes measure once for one layout check", () => {});

test("a factory-created adapter cannot have its validated measure function replaced", () => {});

test("a factory-created adapter does not expose the internal brand as a public property", () => {});

test("a public adapter cannot be created by copying enumerable properties from a valid adapter", () => {});
