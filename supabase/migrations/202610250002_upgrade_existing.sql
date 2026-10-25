-- Apply after 202610250001_core.sql. Transactional, data-preserving migration.
-- Safe to replay against the current TurfOS schema. Never use on an unrelated project.
begin;
create table if not exists public.customer_notes(business_id uuid not null, customer_id uuid not null, notes text not null default '', updated_at timestamptz not null default now(), primary key(business_id,customer_id), foreign key(business_id,customer_id) references public.customers(business_id,id));
alter table public.customer_notes enable row level security;
revoke all on public.customer_notes from anon,authenticated;
grant select on public.customer_notes to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='customer_notes' and policyname='customer_notes_read') then
  create policy customer_notes_read on public.customer_notes for select to authenticated using(public.member_role(business_id) in ('owner','manager'));
 end if;
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name='customers' and column_name='notes') then
  execute 'insert into public.customer_notes(business_id,customer_id,notes) select business_id,id,notes from public.customers where notes <> '''' on conflict(business_id,customer_id) do update set notes=excluded.notes,updated_at=now()';
  execute 'alter table public.customers drop column notes';
 end if;
end $$;
create or replace function public.can_finance(b uuid) returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select coalesce(member_role(b) in ('owner','manager'),false) $$;
create or replace function public.can_collect_payment(b uuid) returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select coalesce(can_finance(b) or exists(select 1 from business_members where business_id=b and user_id=auth.uid() and active and can_collect),false) $$;
create or replace function public.mutate(b uuid,action text,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare rid uuid; token text; r business_members; fid uuid; item jsonb; tz text; sid uuid; role_name text;
begin
 if action='customer' then perform assert_access(b,array['owner','manager','staff']); else perform assert_access(b,array['owner','manager']); end if;
 if action='branch' then
  tz:=coalesce(d->>'timezone','Asia/Dhaka'); if not exists(select 1 from pg_timezone_names where name=tz) then raise exception 'Unknown timezone'; end if;
  if nullif(d->>'id','') is null then
   perform enforce_limit(b,'branches');
   insert into branches(business_id,name,address,timezone) values(b,d->>'name',d->>'address',tz) returning id into rid;
  else
   update branches set name=d->>'name',address=d->>'address',timezone=tz where business_id=b and id=(d->>'id')::uuid returning id into rid;
  end if;
 elsif action='facility' then
  if nullif(d->>'id','') is null then
   perform enforce_limit(b,'resources');
   insert into facilities(business_id,branch_id,name,sport,rate_minor,capacity,durations) values(b,(d->>'branch_id')::uuid,d->>'name',d->>'sport',(d->>'rate_minor')::bigint,coalesce((d->>'capacity')::int,10),array(select jsonb_array_elements_text(d->'durations')::int)) returning id into rid;
   insert into opening_hours(business_id,facility_id,weekday,opens,closes) select b,rid,generate_series(0,6),coalesce(d->>'opens','06:00')::time,coalesce(d->>'closes','23:00')::time;
  else
   fid:=(d->>'id')::uuid;
   perform 1 from facilities where business_id=b and id=fid for update;
   if not found then raise exception 'Facility not found'; end if;
   if exists(select 1 from bookings where facility_id=fid and ends_at>now() and state in ('confirmed','checked_in')) and ((d ? 'hours') or (d ? 'buffer_minutes') or d->>'active'='false') then raise exception 'Resolve upcoming reservations before changing hours, buffers, or archiving'; end if;
   update facilities set name=d->>'name',sport=d->>'sport',rate_minor=(d->>'rate_minor')::bigint,capacity=(d->>'capacity')::int,published=coalesce((d->>'published')::boolean,published),active=coalesce((d->>'active')::boolean,active),buffer_minutes=coalesce((d->>'buffer_minutes')::int,buffer_minutes),durations=array(select jsonb_array_elements_text(d->'durations')::int) where business_id=b and id=fid returning id into rid;
   if d ? 'hours' then
    delete from opening_hours where business_id=b and facility_id=fid;
    for item in select * from jsonb_array_elements(d->'hours') loop
     insert into opening_hours(business_id,facility_id,weekday,opens,closes) values(b,fid,(item->>'weekday')::int,(item->>'opens')::time,(item->>'closes')::time);
    end loop;
   end if;
  end if;
 elsif action='closure' then
  fid:=(d->>'facility_id')::uuid;
  perform 1 from facilities where business_id=b and id=fid for update;
  if not found then raise exception 'Facility not found'; end if;
  if exists(select 1 from bookings where facility_id=fid and state in ('confirmed','checked_in') and starts_at<(d->>'ends_at')::timestamptz and occupied_until>(d->>'starts_at')::timestamptz) then raise exception 'Reschedule or cancel affected bookings first'; end if;
  insert into availability_exceptions(business_id,facility_id,starts_at,ends_at,reason) values(b,fid,(d->>'starts_at')::timestamptz,(d->>'ends_at')::timestamptz,d->>'reason') returning id into rid;
 elsif action='customer' then
  insert into customers(business_id,name,phone,consent) values(b,d->>'name',d->>'phone',coalesce((d->>'consent')::boolean,false)) on conflict(business_id,phone) do update set name=excluded.name,consent=excluded.consent returning id into rid;
  if length(coalesce(d->>'notes',''))>0 then
   if member_role(b) not in ('owner','manager') then raise exception 'Only owners and managers can write private notes'; end if;
   insert into customer_notes(business_id,customer_id,notes) values(b,rid,d->>'notes') on conflict(business_id,customer_id) do update set notes=excluded.notes,updated_at=now();
  end if;
 elsif action='settings' then
  update businesses set name=d->>'name',phone=d->>'phone',city=d->>'city',public_phone=coalesce(d->>'public_phone',''),published=(d->>'published')::boolean,lead_minutes=(d->>'lead_minutes')::int,horizon_days=(d->>'horizon_days')::int where id=b returning id into rid;
  if (d->>'published')::boolean and not exists(select 1 from facilities where business_id=b and active and published) then raise exception 'Create a published facility before publishing'; end if;
 elsif action='invite' then
  perform enforce_limit(b,'seats'); token:=encode(gen_random_bytes(32),'hex');
  insert into invitations(business_id,email,role,token_hash,created_by) values(b,lower(d->>'email'),d->>'role',encode(digest(token,'sha256'),'hex'),auth.uid()) returning id into rid;
  perform audit(b,'team.invited',jsonb_build_object('invitation_id',rid));
  return jsonb_build_object('id',rid,'token',token);
 elsif action='membership' then
  if member_role(b)<>'owner' then raise exception 'Owner required' using errcode='42501'; end if;
  perform 1 from businesses where id=b for update;
  select * into r from business_members where business_id=b and user_id=(d->>'user_id')::uuid for update;
  if not found then raise exception 'Member not found'; end if;
  if r.role='owner' and (d->>'role'<>'owner' or d->>'active'='false') and (select count(*) from business_members where business_id=b and role='owner' and active)<=1 then raise exception 'Cannot remove the final active owner'; end if;
  if d->>'role'='owner' and r.role<>'owner' then raise exception 'Owner transfer requires a separately verified support process'; end if;
  if not r.active and (d->>'active')::boolean then perform enforce_limit(b,'seats'); end if;
  update business_members set role=d->>'role',active=(d->>'active')::boolean,can_collect=(d->>'can_collect')::boolean where business_id=b and user_id=r.user_id returning user_id into rid;
 elsif action='cancel_renewal' then
  if member_role(b)<>'owner' then raise exception 'Owner required'; end if;
  update subscriptions set cancel_at_end=true where business_id=b returning id into rid;
 else raise exception 'Unknown action'; end if;
 if rid is null then raise exception 'Record not found'; end if;
 perform audit(b,action||'.saved',jsonb_build_object('id',rid));
 return jsonb_build_object('id',rid);
end $$;
create or replace function public.record_payment(b uuid,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare r bookings; original payments; net bigint; reversed bigint; amount bigint:=(d->>'amount_minor')::bigint; kind text:=coalesce(d->>'kind','collection'); pid uuid; key uuid:=(d->>'idempotency_key')::uuid;
begin
 perform assert_access(b,array['owner','manager','staff']);
 if not can_collect_payment(b) then raise exception 'Payment permission required' using errcode='42501'; end if;
 select * into r from bookings where business_id=b and id=(d->>'booking_id')::uuid for update;
 if not found then raise exception 'Booking not found'; end if;
 select id into pid from payments where business_id=b and idempotency_key=key;
 if found then return jsonb_build_object('id',pid); end if;
 if amount<=0 then raise exception 'Amount must be positive'; end if;
 select coalesce(sum(case when p.kind='collection' then amount_minor else -amount_minor end),0) into net from payments p where booking_id=r.id;
 if kind='collection' then
  if r.state in ('requested','expired','declined','cancelled') then raise exception 'Cannot collect against this booking state'; end if;
  if amount>r.total_minor-net then raise exception 'Amount exceeds outstanding balance'; end if;
 else
  if member_role(b)<>'owner' then raise exception 'Owner approval required for refunds and reversals' using errcode='42501'; end if;
  select * into original from payments where business_id=b and booking_id=r.id and id=(d->>'original_id')::uuid and payments.kind='collection' for update;
  if not found then raise exception 'Original collection not found'; end if;
  select coalesce(sum(amount_minor),0) into reversed from payments where original_id=original.id;
  if amount>original.amount_minor-reversed then raise exception 'Refund exceeds remaining original payment'; end if;
 end if;
 insert into payments(business_id,booking_id,amount_minor,kind,method,reference,original_id,reason,actor_id,idempotency_key) values(b,r.id,amount,kind,d->>'method',coalesce(d->>'reference',''),(d->>'original_id')::uuid,coalesce(d->>'reason',''),auth.uid(),key) returning id into pid;
 perform audit(b,'payment.'||kind,jsonb_build_object('payment_id',pid,'booking_id',r.id,'amount_minor',amount));
 return jsonb_build_object('id',pid);
end $$;
create or replace function public.platform_mutate(action text,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare rid uuid; inv subscription_invoices; sub subscriptions; n bigint;
begin
 if not is_admin() then raise exception 'Platform administrator with MFA required' using errcode='42501'; end if;
 if action='business_state' then
  if length(d->>'reason')<3 then raise exception 'Reason required'; end if;
  update businesses set state=d->>'state' where id=(d->>'id')::uuid returning id into rid;
 elsif action='plan' then
  insert into plans(slug,version,name,monthly_minor,branches,resources,seats,published) values(d->>'slug',(d->>'version')::int,d->>'name',(d->>'monthly_minor')::bigint,(d->>'branches')::int,(d->>'resources')::int,(d->>'seats')::int,coalesce((d->>'published')::boolean,false)) returning id into rid;
 elsif action='publish_plan' then
  if length(coalesce(d->>'reason',''))<3 then raise exception 'Reason required'; end if;
  update plans set published=true where id=(d->>'id')::uuid and not published returning id into rid;
 elsif action='plan_change' then
  if length(coalesce(d->>'reason',''))<3 then raise exception 'Reason required'; end if;
  select * into sub from subscriptions where id=(d->>'id')::uuid for update;
  if not found then raise exception 'Subscription not found'; end if;
  if not exists(select 1 from plans new_plan join plans old_plan on old_plan.id=sub.plan_id where new_plan.id=(d->>'plan_id')::uuid and new_plan.published and new_plan.branches>=old_plan.branches and new_plan.resources>=old_plan.resources and new_plan.seats>=old_plan.seats) then raise exception 'Only published capacity upgrades are supported'; end if;
  update subscriptions set plan_id=(d->>'plan_id')::uuid where id=sub.id returning id into rid;
 elsif action='subscription' then
  select * into sub from subscriptions where id=(d->>'id')::uuid for update;
  if not found then raise exception 'Subscription not found'; end if;
  if d->>'state'='active' then raise exception 'Record verified invoice payment to activate'; end if;
  if length(d->>'reason')<3 then raise exception 'Reason required'; end if;
  update subscriptions set plan_id=(d->>'plan_id')::uuid,state=d->>'state' where id=sub.id returning id into rid;
 elsif action='invoice' then
  insert into subscription_invoices(subscription_id,amount_minor,due_at) select s.id,p.monthly_minor,(d->>'due_at')::timestamptz from subscriptions s join plans p on p.id=s.plan_id where s.id=(d->>'subscription_id')::uuid returning id into rid;
 elsif action='subscription_payment' then
  select * into inv from subscription_invoices where id=(d->>'invoice_id')::uuid for update;
  if not found then raise exception 'Invoice not found'; end if;
  if exists(select 1 from subscription_payments where reference=d->>'reference') then raise exception 'Payment reference already used'; end if;
  select coalesce(sum(amount_minor),0) into n from subscription_payments where invoice_id=inv.id;
  if (d->>'amount_minor')::bigint>inv.amount_minor-n then raise exception 'Payment exceeds invoice balance'; end if;
  insert into subscription_payments(invoice_id,amount_minor,reference,verified_by) values(inv.id,(d->>'amount_minor')::bigint,d->>'reference',auth.uid()) returning id into rid;
  if n+(d->>'amount_minor')::bigint=inv.amount_minor then
   update subscriptions set state='active',period_end=greatest(now(),period_end)+interval '1 month' where id=inv.subscription_id;
  end if;
 elsif action='support' then
  update support_tickets set state=d->>'state',resolution=d->>'resolution',assigned_to=auth.uid() where id=(d->>'id')::uuid returning id into rid;
 else raise exception 'Unknown administrative action'; end if;
 if rid is null then raise exception 'Record not found'; end if;
 perform audit(null,'platform.'||action,jsonb_build_object('id',rid,'reason',d->>'reason'));
 return jsonb_build_object('id',rid);
end $$;
create or replace function public.workspace_access(b uuid) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare writable boolean:=true;
begin
 perform assert_access(b,array['owner','manager','staff','viewer'],false);
 begin perform assert_access(b,array['owner','manager','staff']); exception when insufficient_privilege then writable:=false; end;
 return jsonb_build_object('writable',writable,'finance',can_finance(b),'collect',can_collect_payment(b));
end $$;
create or replace function public.business_report(b uuid,from_at timestamptz,to_at timestamptz,branch uuid default null) returns jsonb language plpgsql stable security definer set search_path=public,extensions,pg_temp as $$
declare booking_value bigint; receipts bigint; outstanding bigint; booked_minutes numeric; open_minutes numeric; breakdown jsonb;
begin
 perform assert_access(b,array['owner','manager'],false);
 if to_at<=from_at or to_at-from_at>interval '32 days' then raise exception 'Choose a range of 32 days or less'; end if;
 if branch is not null and not exists(select 1 from branches where id=branch and business_id=b) then raise exception 'Branch not found'; end if;
 select coalesce(sum(k.total_minor),0),coalesce(sum(extract(epoch from least(k.ends_at,to_at)-greatest(k.starts_at,from_at))/60),0)
 into booking_value,booked_minutes from bookings k join facilities f on f.id=k.facility_id and f.business_id=b where k.business_id=b and k.state in ('confirmed','checked_in','completed','no_show') and k.starts_at<to_at and k.ends_at>from_at and (branch is null or f.branch_id=branch);
 select coalesce(sum(case when p.kind='collection' then p.amount_minor else -p.amount_minor end),0) into receipts from payments p join bookings k on k.id=p.booking_id and k.business_id=b join facilities f on f.id=k.facility_id and f.business_id=b where p.business_id=b and p.created_at>=from_at and p.created_at<to_at and (branch is null or f.branch_id=branch);
 select coalesce(sum(greatest(k.total_minor-coalesce((select sum(case when p.kind='collection' then p.amount_minor else -p.amount_minor end) from payments p where p.booking_id=k.id),0),0)),0) into outstanding from bookings k join facilities f on f.id=k.facility_id and f.business_id=b where k.business_id=b and k.state in ('confirmed','checked_in','completed','no_show') and k.starts_at<to_at and k.ends_at>from_at and (branch is null or f.branch_id=branch);
 -- P0 Bangladesh facilities use 30-minute increments; count bookable cells, excluding closures.
 select count(*)*30 into open_minutes from facilities f join branches br on br.id=f.branch_id join lateral generate_series((from_at at time zone br.timezone)::date,(to_at at time zone br.timezone)::date,interval '1 day') d on true join opening_hours h on h.facility_id=f.id and h.weekday=extract(dow from d) join lateral generate_series((d::date+h.opens) at time zone br.timezone,((d::date+h.closes) at time zone br.timezone)-interval '30 minutes',interval '30 minutes') cell on true where f.business_id=b and f.active and br.active and (branch is null or f.branch_id=branch) and cell>=from_at and cell+interval '30 minutes'<=to_at and not exists(select 1 from availability_exceptions x where x.facility_id=f.id and x.starts_at<cell+interval '30 minutes' and x.ends_at>cell);
 select coalesce(jsonb_agg(jsonb_build_object('facility_id',x.id,'name',x.name,'bookings',x.count,'value_minor',x.value_minor) order by x.name),'[]') into breakdown from (select f.id,f.name,count(k.id)::int as count,coalesce(sum(k.total_minor),0)::bigint as value_minor from facilities f left join bookings k on k.facility_id=f.id and k.business_id=b and k.state in ('confirmed','checked_in','completed','no_show') and k.starts_at<to_at and k.ends_at>from_at where f.business_id=b and (branch is null or f.branch_id=branch) group by f.id,f.name) x;
 return jsonb_build_object('booking_value_minor',booking_value,'collected_minor',receipts,'outstanding_minor',outstanding,'booked_minutes',booked_minutes,'open_minutes',open_minutes,'occupancy_percent',case when open_minutes>0 then round(booked_minutes*100/open_minutes,1) else null end,'breakdown',breakdown);
end $$;
create or replace function public.booking_balance(b uuid,booking uuid) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare total bigint;net bigint;
begin
 perform assert_access(b,array['owner','manager','staff'],false);
 if not can_collect_payment(b) then raise exception 'Payment permission required'; end if;
 select total_minor into total from bookings where business_id=b and id=booking;
 if total is null then raise exception 'Booking not found'; end if;
 select coalesce(sum(case when kind='collection' then amount_minor else -amount_minor end),0) into net from payments where business_id=b and booking_id=booking;
 return jsonb_build_object('total_minor',total,'collected_minor',net,'due_minor',greatest(0,total-net));
end $$;
create or replace function public.refresh_subscription_states() returns int language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare changed int:=0;n int;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Access denied'; end if;
 update subscriptions set state='read_only' where state='trialing' and period_end<now();get diagnostics n=row_count;changed:=changed+n;
 update subscriptions set state='read_only' where state in ('active','past_due','grace') and cancel_at_end and period_end<now();get diagnostics n=row_count;changed:=changed+n;
 update subscriptions set state='read_only' where state in ('active','past_due','grace') and not cancel_at_end and period_end+make_interval(days=>grace_days)<now();get diagnostics n=row_count;changed:=changed+n;
 update subscriptions set state='grace' where state in ('active','past_due') and not cancel_at_end and period_end+interval '1 day'<now() and period_end+make_interval(days=>grace_days)>=now();get diagnostics n=row_count;changed:=changed+n;
 update subscriptions set state='past_due' where state='active' and not cancel_at_end and period_end<now();get diagnostics n=row_count;changed:=changed+n;
 return changed;
end $$;
revoke execute on function public.can_collect_payment(uuid),public.business_report(uuid,timestamptz,timestamptz,uuid),public.booking_balance(uuid,uuid),public.refresh_subscription_states() from public,anon,authenticated;
grant execute on function public.can_collect_payment(uuid),public.business_report(uuid,timestamptz,timestamptz,uuid),public.booking_balance(uuid,uuid) to authenticated;
grant execute on function public.refresh_subscription_states() to service_role;
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef loop
  execute format('alter function %s set search_path to public, extensions, pg_temp',f.signature);
 end loop;
end $$;
commit;
