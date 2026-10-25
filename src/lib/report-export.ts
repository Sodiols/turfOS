export type Report = {
  booking_value_minor: number;
  collected_minor: number;
  outstanding_minor: number;
  booked_minutes: number;
  open_minutes: number;
  occupancy_percent: number | null;
  breakdown: { facility_id: string; name: string; bookings: number; value_minor: number }[];
};

export function csvCell(value: string | number | null) {
  const raw = value === null ? "" : String(value);
  const safe = /^[\s]*[=+\-@]/.test(raw) ? `'${raw}` : raw;
  return `"${safe.replaceAll('"', '""')}"`;
}

export function reportCsv(report: Report, meta: { start: string; end: string; timezone: string; branch: string }) {
  const money = (minor: number) => (minor / 100).toFixed(2);
  const rows: (string | number | null)[][] = [
    ["TurfOS report", ""],
    ["From", meta.start], ["Through", meta.end], ["Time zone", meta.timezone], ["Branch", meta.branch],
    [],
    ["Metric", "Value"],
    ["Booking value (BDT)", money(report.booking_value_minor)],
    ["Collected (BDT)", money(report.collected_minor)],
    ["Outstanding (BDT)", money(report.outstanding_minor)],
    ["Booked minutes", report.booked_minutes], ["Open minutes", report.open_minutes],
    ["Occupancy (%)", report.occupancy_percent],
    [],
    ["Facility", "Bookings", "Booking value (BDT)"],
    ...report.breakdown.map(item => [item.name, item.bookings, money(item.value_minor)]),
  ];
  return '\uFEFF' + rows.map(row => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}
