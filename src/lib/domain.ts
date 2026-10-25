import { z } from "zod";
import { fromZonedTime, formatInTimeZone } from "date-fns-tz";
export type Role = "owner" | "manager" | "staff" | "viewer";
export type Row = { id: string; business_id: string; [key: string]: unknown };
export type Business = { id: string; slug: string; name: string; city: string; phone: string; public_phone: string; published: boolean; lead_minutes: number; horizon_days: number };
export type Member = { user_id: string; role: Role; active: boolean; can_collect: boolean };
export type Branch = { id: string; name: string; address: string; timezone: string; active: boolean };
export type Facility = { id: string; branch_id: string; name: string; sport: string; rate_minor: number; capacity: number; durations: number[]; buffer_minutes: number; active: boolean; published: boolean };
export type Booking = { id: string; facility_id: string; customer_id: string; ref: string; starts_at: string; ends_at: string; state: string; source: string; total_minor: number; notes: string; version: number };
export type Customer = { id: string; name: string; phone: string; consent: boolean };
export type Payment = { id: string; booking_id: string; amount_minor: number; kind: string; method: string; reference: string; reason: string; original_id: string | null; created_at: string };
export const money = (minor: number) => new Intl.NumberFormat("en-BD", { style: "currency", currency: "BDT", maximumFractionDigits: minor % 100 ? 2 : 0 }).format(minor / 100);
export const localDate = (instant = new Date(), tz = "Asia/Dhaka") => formatInTimeZone(instant,tz,"yyyy-MM-dd");
export const displayTime = (instant: string, tz = "Asia/Dhaka") => formatInTimeZone(new Date(instant),tz,"d MMM, h:mm a");
export function toUTC(local: string, tz: string) { const date=fromZonedTime(local,tz); if(!Number.isFinite(date.getTime()) || formatInTimeZone(date,tz,"yyyy-MM-dd'T'HH:mm")!==local) throw new Error("This local time is invalid in the branch timezone."); return date.toISOString(); }
export function normalizePhone(value: string) { let p=value.replace(/[\s()-]/g,""); if(/^01[0-9]{9}$/.test(p)) p="+88"+p; if(!/^\+[0-9]{8,15}$/.test(p)) throw new Error("Enter a phone with country code, for example +8801712345678."); return p; }
export function minorUnits(value: string) { if(!/^\d{1,9}(\.\d{1,2})?$/.test(value)) throw new Error("Enter a positive amount with at most two decimal places."); const [whole,decimal=""]=value.split("."); return Number(whole)*100+Number(decimal.padEnd(2,"0")); }
export function balance(total: number, payments: Payment[]) { const net=payments.reduce((n,p)=>n+(p.kind==="collection"?p.amount_minor:-p.amount_minor),0); return { net, due: Math.max(0,total-net), credit: Math.max(0,net-total) }; }
export const uuid=z.string().uuid();
export const guestSchema=z.object({ facility_id:uuid, starts_at:z.iso.datetime({offset:true}), ends_at:z.iso.datetime({offset:true}), customer_name:z.string().trim().min(2).max(100), phone:z.string().transform(normalizePhone), consent:z.literal(true), idempotency_key:uuid, website:z.string().max(0).optional() });
export const navigation=[['overview','Overview'],['calendar','Calendar'],['bookings','Bookings'],['facilities','Facilities'],['customers','Customers'],['payments','Payments'],['reports','Reports'],['team','Team'],['settings','Settings'],['subscription','Subscription'],['help','Help']] as const;
export function allowedNav(role: Role,finance: boolean) { return navigation.filter(([key])=> role==="viewer"?["overview","calendar","help"].includes(key):key==="subscription"?role==="owner":["facilities","reports","team","settings"].includes(key)?["owner","manager"].includes(role):key==="payments"?finance:true); }
export function safeReturnPath(value: string | null) { return value && value.startsWith("/") && !value.startsWith("//") && !/[\\\r\n]/.test(value) ? value : "/workspaces"; }
