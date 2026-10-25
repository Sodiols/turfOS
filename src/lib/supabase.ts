import "server-only";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
export const configured = () => Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
export async function database() { if(!configured()) throw new Error("Supabase is not configured. Follow the setup guide to connect this installation."); const jar=await cookies(); return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{cookies:{getAll:()=>jar.getAll(),setAll(items){try { items.forEach(({name,value,options})=>jar.set(name,value,options)); } catch { /* Server Component: proxy refreshes cookies. */ }}}}); }
export function publicDatabase(){ if(!configured() || !process.env.SUPABASE_SECRET_KEY) throw new Error("Public bookings are unavailable until the database connection is configured."); return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.SUPABASE_SECRET_KEY,{auth:{persistSession:false,autoRefreshToken:false}}); }
