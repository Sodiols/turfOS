import { getWorkspace } from "@/lib/workspace";
import { calendarBounds, calendarDays, slotDefault, type CalendarView } from "@/lib/calendar";
import { localDate, type Branch, type Facility } from "@/lib/domain";
import { PageTitle, Empty } from "./ui";
import { NewBooking } from "./workspace-forms";
import { CalendarBoard, type ScheduleItem } from "./calendar-board";

type Query = { date?: string; branch?: string; view?: string; facility?: string; slot?: string };

export async function CalendarWorkspace({ slug, query }: { slug: string; query: Query }) {
  const { db, business, member, writable } = await getWorkspace(slug);
  const { data: branchesData, error: branchesError } = await db.from("branches").select("*").eq("business_id", business.id).order("name");
  if (branchesError) throw new Error(branchesError.message);
  const branches = (branchesData ?? []) as Branch[];
  const selectedBranch = branches.find(item => item.id === query.branch);
  const timezone = selectedBranch?.timezone ?? branches[0]?.timezone ?? "Asia/Dhaka";
  const view: CalendarView = query.view === "week" || query.view === "month" ? query.view : "day";
  let date = localDate(new Date(), timezone);
  if (query.date) {
    try { calendarDays(query.date, "day"); date = query.date; } catch { /* use today */ }
  }
  const bounds = calendarBounds(date, view, timezone);
  const { data: facilityData, error: facilityError } = await db.from("facilities").select("*").eq("business_id", business.id).order("name");
  if (facilityError) throw new Error(facilityError.message);
  const facilities = ((facilityData ?? []) as Facility[]).filter(item => !selectedBranch || item.branch_id === selectedBranch.id);
  const [{ data: schedule, error: scheduleError }, { data: hours, error: hoursError }, { data: closures, error: closuresError }] = await Promise.all([
    db.rpc("schedule", { b: business.id, s: bounds.start, e: bounds.end }),
    db.from("opening_hours").select("facility_id,weekday,opens,closes").eq("business_id", business.id),
    db.from("availability_exceptions").select("facility_id,starts_at,ends_at,reason").eq("business_id", business.id).lt("starts_at", bounds.end).gt("ends_at", bounds.start),
  ]);
  if (scheduleError || hoursError || closuresError) throw new Error(scheduleError?.message ?? hoursError?.message ?? closuresError?.message);
  const facilityIds = new Set(facilities.map(item => item.id));
  const reservations = ((schedule ?? []) as ScheduleItem[]).filter(item => facilityIds.has(item.facility_id));
  let prefill: { facilityId: string; start: string; end: string } | undefined;
  const chosen = facilities.find(item => item.id === query.facility && item.active);
  if (view === "day" && chosen && query.slot && writable && member.role !== "viewer") {
    try {
      const duration = Math.min(...chosen.durations);
      const slot = slotDefault(date, query.slot, duration);
      prefill = { facilityId: chosen.id, start: slot.start, end: slot.end };
    } catch { /* invalid slot is ignored */ }
  }
  const action = writable && member.role !== "viewer" && facilities.length
    ? <NewBooking key={prefill ? `${prefill.facilityId}:${prefill.start}` : "new"} slug={slug} facilities={facilities} branches={branches} initialDate={date} prefill={prefill}/>
    : null;
  return <>
    <PageTitle title="Calendar" description={`Reserved sessions in ${timezone}. Pending requests do not reserve time.`} action={action}/>
    <form className="toolbar"><label>Date <input type="date" name="date" defaultValue={date}/></label><label>View <select name="view" defaultValue={view}><option value="day">Day</option><option value="week">Week</option><option value="month">Month</option></select></label><label>Branch <select name="branch" defaultValue={selectedBranch?.id ?? ""}><option value="">All branches</option>{branches.map(item => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label><button className="button" type="submit">Show schedule</button></form>
    {!facilities.length ? <Empty title="No facilities yet" description="Add your first ground or court to see its calendar." href={member.role === "viewer" ? undefined : `/app/${slug}/facilities`} label="Add facility"/> : <CalendarBoard slug={slug} date={date} view={view} timezone={timezone} branchId={selectedBranch?.id} facilities={facilities} branches={branches} bookings={reservations} hours={hours ?? []} closures={closures ?? []} writable={writable && member.role !== "viewer"}/>}
  </>;
}
