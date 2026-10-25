import { NextRequest } from "next/server";
import { getWorkspace } from "@/lib/workspace";
import { localDate, toUTC } from "@/lib/domain";
import { reportCsv, type Report } from "@/lib/report-export";

export async function GET(request: NextRequest, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const { db, business, member } = await getWorkspace(slug);
  if (!(["owner", "manager"] as string[]).includes(member.role)) return new Response("Forbidden", { status: 403 });
  const url = new URL(request.url);
  const range = url.searchParams.get("range") ?? "1";
  if (!["1", "7", "30"].includes(range)) return new Response("Invalid range", { status: 400 });
  const branchId = url.searchParams.get("branch") || null;
  const { data: branches, error: branchError } = await db.from("branches").select("id,name,timezone").eq("business_id", business.id);
  if (branchError) throw new Error(branchError.message);
  const branch = branchId ? branches?.find(item => item.id === branchId) : null;
  if (branchId && !branch) return new Response("Branch not found", { status: 404 });
  const timezone = branch?.timezone ?? branches?.[0]?.timezone ?? "Asia/Dhaka";
  const requestedDate = url.searchParams.get("date");
  if (requestedDate && !/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)) return new Response("Invalid date", { status: 400 });
  const date = requestedDate ?? localDate(new Date(), timezone);
  const day = Date.parse(`${date}T00:00:00Z`);
  if (!Number.isFinite(day) || new Date(day).toISOString().slice(0, 10) !== date) return new Response("Invalid date", { status: 400 });
  const startDay = new Date(day - (Number(range) - 1) * 86400000).toISOString().slice(0, 10);
  const endDay = new Date(day + 86400000).toISOString().slice(0, 10);
  const { data, error } = await db.rpc("business_report", {
    b: business.id,
    from_at: toUTC(`${startDay}T00:00`, timezone),
    to_at: toUTC(`${endDay}T00:00`, timezone),
    branch: branchId,
  });
  if (error) throw new Error(error.message);
  const csv = reportCsv(data as Report, { start: startDay, end: date, timezone, branch: branch?.name ?? "All branches" });
  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="turfos-report-${date}.csv"`,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
