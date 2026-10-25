import { describe, expect, it } from "vitest";
import { csvCell, reportCsv } from "../src/lib/report-export";

describe("report CSV", () => {
  it("escapes spreadsheet formulas, quotes, and embedded line breaks", () => {
    expect(csvCell('=IMPORTXML("x", "y")')).toBe('"\'=IMPORTXML(""x"", ""y"")"');
    expect(csvCell('  +1')).toBe('"\'  +1"');
    expect(csvCell('Court "A"\nNorth')).toBe('"Court ""A""\nNorth"');
  });

  it("exports exact minor-unit amounts and a facility breakdown", () => {
    const csv = reportCsv({
      booking_value_minor: 10501,
      collected_minor: 5000,
      outstanding_minor: 5501,
      booked_minutes: 90,
      open_minutes: 180,
      occupancy_percent: 50,
      breakdown: [{ facility_id: "x", name: "North court", bookings: 1, value_minor: 10501 }],
    }, { start: "2026-10-24", end: "2026-10-25", timezone: "Asia/Dhaka", branch: "All branches" });
    expect(csv).toContain('"Booking value (BDT)","105.01"');
    expect(csv).toContain('"North court","1","105.01"');
    expect(csv.startsWith("\uFEFF")).toBe(true);
  });
});
