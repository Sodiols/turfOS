import { describe, expect, it } from "vitest";
import { calendarBounds, calendarDays, slotDefault } from "../src/lib/calendar";

describe("calendar dates", () => {
  it("starts weeks on Monday and uses exact month bounds", () => {
    expect(calendarDays("2026-10-25", "week")).toEqual(["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]);
    expect(calendarDays("2026-02-15", "month")).toHaveLength(28);
    expect(calendarDays("2028-02-15", "month")).toHaveLength(29);
  });

  it("converts local boundaries to UTC, including daylight saving shifts", () => {
    const range = calendarBounds("2026-03-08", "day", "America/New_York");
    expect(range.start).toBe("2026-03-08T05:00:00.000Z");
    expect(range.end).toBe("2026-03-09T04:00:00.000Z");
  });

  it("prefills a slot with a crossing-midnight duration", () => {
    expect(slotDefault("2026-10-25", "23:30", 60)).toEqual({ start: "2026-10-25T23:30", end: "2026-10-26T00:30" });
    expect(() => slotDefault("2026-10-25", "23:45", 60)).toThrow();
  });
});
