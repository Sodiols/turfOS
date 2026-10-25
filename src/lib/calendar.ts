import { toUTC } from "./domain";

export type CalendarView = "day" | "week" | "month";

export function calendarDays(date: string, view: CalendarView) {
  const anchor = new Date(`${date}T00:00:00Z`);
  if (!Number.isFinite(anchor.getTime()) || anchor.toISOString().slice(0, 10) !== date) throw new Error("Invalid calendar date");
  let first = anchor;
  let count = 1;
  if (view === "week") {
    first = new Date(anchor.getTime() - ((anchor.getUTCDay() + 6) % 7) * 86400000);
    count = 7;
  } else if (view === "month") {
    first = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), 1));
    count = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + 1, 0)).getUTCDate();
  }
  return Array.from({ length: count }, (_, i) => new Date(first.getTime() + i * 86400000).toISOString().slice(0, 10));
}

export function calendarBounds(date: string, view: CalendarView, timezone: string) {
  const days = calendarDays(date, view);
  const last = new Date(`${days.at(-1)}T00:00:00Z`);
  const next = new Date(last.getTime() + 86400000).toISOString().slice(0, 10);
  return { days, start: toUTC(`${days[0]}T00:00`, timezone), end: toUTC(`${next}T00:00`, timezone) };
}

export function slotDefault(date: string, time: string, durationMinutes: number) {
  if (!/^([01]\d|2[0-3]):(00|30)$/.test(time)) throw new Error("Invalid booking slot");
  const start = `${date}T${time}`;
  const end = new Date(Date.parse(`${start}:00Z`) + durationMinutes * 60000);
  return { start, end: end.toISOString().slice(0, 16) };
}
