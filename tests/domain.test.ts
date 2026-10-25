import { describe, it, expect } from "vitest";
import { normalizePhone, minorUnits, toUTC, balance, safeReturnPath } from "../src/lib/domain";

describe("financial and booking input boundaries", () => {
  it("uses exact minor units", () => {
    expect(minorUnits("1999.05")).toBe(199905);
    expect(() => minorUnits("1.001")).toThrow();
    expect(() => minorUnits("-1")).toThrow();
  });
  it("reconciles collections and refunds", () => {
    const entries = [{ kind: "collection", amount_minor: 50000 }, { kind: "collection", amount_minor: 30000 }, { kind: "refund", amount_minor: 10000 }];
    expect(balance(120000, entries as never)).toEqual({ net: 70000, due: 50000, credit: 0 });
  });
  it("normalizes Bangladesh phone numbers", () => {
    expect(normalizePhone("01712 345678")).toBe("+8801712345678");
    expect(() => normalizePhone("12345")).toThrow();
  });
  it("converts branch time to UTC", () => {
    expect(toUTC("2026-10-25T18:30", "Asia/Dhaka")).toBe("2026-10-25T12:30:00.000Z");
  });
  it("rejects unsafe redirect paths", () => {
    expect(safeReturnPath("//evil.test")).toBe("/workspaces");
    expect(safeReturnPath("/\\evil.test")).toBe("/workspaces");
    expect(safeReturnPath("/app/workspace/overview")).toBe("/app/workspace/overview");
  });
});
