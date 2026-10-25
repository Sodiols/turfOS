import Link from "next/link";
import { formatInTimeZone } from "date-fns-tz";
import { toUTC, type Branch, type Facility } from "@/lib/domain";
import { calendarBounds, type CalendarView } from "@/lib/calendar";

export type ScheduleItem = { id: string; facility_id: string; starts_at: string; ends_at: string; state: string; ref: string };
type Hour = { facility_id: string; weekday: number; opens: string; closes: string };
type Closure = { facility_id: string; starts_at: string; ends_at: string; reason: string };

type Props = {
  slug: string; date: string; view: CalendarView; timezone: string; branchId?: string;
  facilities: Facility[]; branches: Branch[]; bookings: ScheduleItem[];
  hours: Hour[]; closures: Closure[]; writable: boolean;
};

function timeLabel(time: string) {
  const [hour, minute] = time.split(":").map(Number);
  return `${hour % 12 || 12}:${String(minute).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`;
}

export function CalendarBoard({ slug, date, view, timezone, branchId, facilities, branches, bookings, hours, closures, writable }: Props) {
  const bounds = calendarBounds(date, view, timezone);
  if (view !== "day") return <div className={`calendar-days ${view}`}>
    {bounds.days.map(day => {
      const start = Date.parse(toUTC(`${day}T00:00`, timezone));
      const next = new Date(Date.parse(`${day}T00:00:00Z`) + 86400000).toISOString().slice(0, 10);
      const end = Date.parse(toUTC(`${next}T00:00`, timezone));
      const daily = bookings.filter(item => Date.parse(item.starts_at) < end && Date.parse(item.ends_at) > start);
      return <Link className={`calendar-day ${day === date ? "selected" : ""}`} key={day} href={`/app/${slug}/calendar?view=day&date=${day}${branchId ? `&branch=${branchId}` : ""}`}>
        <time dateTime={day}>{formatInTimeZone(new Date(`${day}T12:00:00Z`), "UTC", "EEE d MMM")}</time>
        <strong>{daily.length} {daily.length === 1 ? "session" : "sessions"}</strong>
        <span>{[...new Set(daily.map(item => facilities.find(facility => facility.id === item.facility_id)?.name).filter(Boolean))].slice(0, 3).join(" · ") || "No reservations"}</span>
      </Link>;
    })}
  </div>;

  const slots = Array.from({ length: 48 }, (_, i) => `${String(Math.floor(i / 2)).padStart(2, "0")}:${i % 2 ? "30" : "00"}`);
  return <div className="timeline-wrap" role="region" aria-label={`Facility timeline for ${date}`} tabIndex={0}>
    <table className="timeline-table"><thead><tr><th scope="col">Time</th>{facilities.map(facility => <th scope="col" key={facility.id}>{facility.name}<small>{branches.find(branch => branch.id === facility.branch_id)?.name}</small></th>)}</tr></thead>
      <tbody>{slots.map((time, index) => {
        let slotStart: number;
        try { slotStart = Date.parse(toUTC(`${date}T${time}`, timezone)); } catch { slotStart = NaN; }
        const slotEnd = slotStart + 30 * 60000;
        return <tr key={time}><th scope="row">{timeLabel(time)}</th>{facilities.map(facility => {
          if (!Number.isFinite(slotStart)) return <td className="timeline-closed" key={facility.id}>Unavailable</td>;
          const reservation = bookings.find(item => item.facility_id === facility.id && Date.parse(item.starts_at) < slotEnd && Date.parse(item.ends_at) > slotStart);
          if (reservation) return <td className="timeline-reserved" key={facility.id}><Link href={`/app/${slug}/bookings/${reservation.id}`} aria-label={`${facility.name}, ${timeLabel(time)}, booking ${reservation.ref}`}>{Date.parse(reservation.starts_at) >= slotStart || index === 0 ? reservation.ref : "Reserved"}</Link></td>;
          const bookableEnd = slotStart + Math.min(...facility.durations) * 60000;
          const exception = closures.find(item => item.facility_id === facility.id && Date.parse(item.starts_at) < bookableEnd && Date.parse(item.ends_at) > slotStart);
          if (exception) return <td className="timeline-closed" key={facility.id} title={exception.reason}>Closed</td>;
          if (bookings.some(item => item.facility_id === facility.id && Date.parse(item.starts_at) < bookableEnd && Date.parse(item.ends_at) > slotStart)) return <td className="timeline-closed" key={facility.id}>Unavailable</td>;
          const branch = branches.find(item => item.id === facility.branch_id);
          const branchTimezone = branch?.timezone ?? timezone;
          const localStart = formatInTimeZone(new Date(slotStart), branchTimezone, "yyyy-MM-dd HH:mm");
          const localEnd = formatInTimeZone(new Date(bookableEnd), branchTimezone, "yyyy-MM-dd HH:mm");
          const weekday = new Date(`${localStart.slice(0, 10)}T00:00:00Z`).getUTCDay();
          const opening = hours.some(item => item.facility_id === facility.id && item.weekday === weekday && localEnd.slice(0, 10) === localStart.slice(0, 10) && localStart.slice(11) >= item.opens.slice(0, 5) && localEnd.slice(11) <= item.closes.slice(0, 5));
          if (!facility.active || !branch?.active || !opening) return <td className="timeline-closed" key={facility.id}>Closed</td>;
          const href = `/app/${slug}/calendar?view=day&date=${date}${branchId ? `&branch=${branchId}` : ""}&facility=${facility.id}&slot=${time}`;
          return <td className="timeline-open" key={facility.id}>{writable ? <Link href={href} aria-label={`Book ${facility.name} at ${timeLabel(time)} on ${date}`}>+ Book</Link> : <span>Available</span>}</td>;
        })}</tr>;
      })}</tbody>
    </table>
  </div>;
}
