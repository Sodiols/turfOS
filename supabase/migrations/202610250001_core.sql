-- TurfOS P0. All money is integer paisa; all instants are timestamptz.
create extension if not exists btree_gist;
create extension if not exists pgcrypto;
create table public.profiles(user_id uuid primary key references auth.users(id), name text not null default '', created_at timestamptz not null default now());
create table public.platform_admins(user_id uuid primary key references auth.users(id), active boolean not null default true);
create table public.plans(id uuid primary key default gen_random_uuid(), slug text not null, version int not null default 1, name text not null, monthly_minor bigint not null check(monthly_minor>=0), branches int not null check(branches>0), resources int not null check(resources>0), seats int not null check(seats>0), published boolean not null default false, unique(slug,version));
create table public.plan_entitlements(plan_id uuid references public.plans(id), feature text not null, enabled boolean not null default false, primary key(plan_id,feature));
insert into public.plans(slug,name,monthly_minor,branches,resources,seats,published) values ('starter','Starter',99900,1,1,2,true),('business','Business',199900,1,3,5,true),('pro','Pro',399900,3,10,15,true);
create table public.businesses(id uuid primary key default gen_random_uuid(), slug text unique not null check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'), name text not null check(length(name) between 2 and 100), phone text not null default '', city text not null default '', state text not null default 'active' check(state in ('active','suspended')), published boolean not null default false, public_phone text not null default '', lead_minutes int not null default 60 check(lead_minutes>=0), horizon_days int not null default 60 check(horizon_days between 1 and 365), request_expiry_hours int not null default 24 check(request_expiry_hours between 1 and 168), created_at timestamptz not null default now());
create table public.business_members(business_id uuid references public.businesses(id), user_id uuid references auth.users(id), role text not null check(role in ('owner','manager','staff','viewer')), active boolean not null default true, can_collect boolean not null default false, created_at timestamptz not null default now(), primary key(business_id,user_id));
create index members_user on public.business_members(user_id);
create table public.subscriptions(id uuid primary key default gen_random_uuid(), business_id uuid not null unique references public.businesses(id), plan_id uuid not null references public.plans(id), state text not null default 'trialing' check(state in ('trialing','active','past_due','grace','read_only','cancelled')), period_end timestamptz not null default now()+interval '14 days', grace_days int not null default 7 check(grace_days between 0 and 30), cancel_at_end boolean not null default false);
create table public.branches(id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id), name text not null, address text not null, timezone text not null default 'Asia/Dhaka', active boolean not null default true, unique(business_id,id));
create table public.facilities(id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id), branch_id uuid not null, name text not null, sport text not null, capacity int not null default 10 check(capacity>0), rate_minor bigint not null check(rate_minor>=0), durations int[] not null default '{60,90,120}', buffer_minutes int not null default 0 check(buffer_minutes between 0 and 60), active boolean not null default true, published boolean not null default true, unique(business_id,id), foreign key(business_id,branch_id) references public.branches(business_id,id), check(array_length(durations,1)>0 and durations <@ array[30,60,90,120,150,180,240]));
create table public.opening_hours(id uuid primary key default gen_random_uuid(), business_id uuid not null, facility_id uuid not null, weekday int not null check(weekday between 0 and 6), opens time not null, closes time not null, check(closes>opens), foreign key(business_id,facility_id) references public.facilities(business_id,id), exclude using gist(facility_id with =, weekday with =, numrange(extract(epoch from opens)::numeric,extract(epoch from closes)::numeric,'[)') with &&));
create table public.availability_exceptions(id uuid primary key default gen_random_uuid(), business_id uuid not null, facility_id uuid not null, starts_at timestamptz not null, ends_at timestamptz not null, reason text not null, check(ends_at>starts_at), foreign key(business_id,facility_id) references public.facilities(business_id,id));
create table public.customers(id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id), name text not null check(length(name) between 2 and 100), phone text not null check(phone ~ '^\+[0-9]{8,15}$'), consent boolean not null default false, created_at timestamptz not null default now(), unique(business_id,id), unique(business_id,phone));
create table public.customer_notes(business_id uuid not null, customer_id uuid not null, notes text not null default '', updated_at timestamptz not null default now(), primary key(business_id,customer_id), foreign key(business_id,customer_id) references public.customers(business_id,id));
create table public.bookings(id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id), facility_id uuid not null, customer_id uuid not null, ref text not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)), starts_at timestamptz not null, ends_at timestamptz not null, occupied_until timestamptz not null, state text not null check(state in ('requested','confirmed','checked_in','completed','cancelled','no_show','expired','declined')), source text not null check(source in ('manual','phone','whatsapp','public')), total_minor bigint not null check(total_minor>=0), price_snapshot jsonb not null, notes text not null default '', created_by uuid references auth.users(id), idempotency_key uuid not null, expires_at timestamptz, version int not null default 1, created_at timestamptz not null default now(), unique(business_id,id), unique(business_id,ref), unique(business_id,idempotency_key), foreign key(business_id,facility_id) references public.facilities(business_id,id), foreign key(business_id,customer_id) references public.customers(business_id,id), check(ends_at>starts_at and occupied_until>=ends_at), exclude using gist(facility_id with =, tstzrange(starts_at,occupied_until,'[)') with &&) where(state in ('confirmed','checked_in','completed','no_show')));
create index bookings_calendar on public.bookings(business_id,starts_at,facility_id);
create table public.booking_events(id uuid primary key default gen_random_uuid(), business_id uuid not null, booking_id uuid not null, actor_id uuid, action text not null, details jsonb not null default '{}', created_at timestamptz not null default now(), foreign key(business_id,booking_id) references public.bookings(business_id,id));
create table public.payments(id uuid primary key default gen_random_uuid(), business_id uuid not null, booking_id uuid not null, amount_minor bigint not null check(amount_minor>0), kind text not null check(kind in ('collection','refund','reversal')), method text not null check(method in ('cash','bkash','nagad','bank','other')), reference text not null default '', original_id uuid, reason text not null default '', actor_id uuid not null references auth.users(id), idempotency_key uuid not null, created_at timestamptz not null default now(), unique(business_id,id), unique(business_id,idempotency_key), foreign key(business_id,booking_id) references public.bookings(business_id,id), foreign key(business_id,original_id) references public.payments(business_id,id), check(kind='collection' or (original_id is not null and length(reason)>2)), check(method='cash' or length(reference)>2));
create unique index payment_reference on public.payments(business_id,reference) where reference<>'' and kind='collection';
create index payment_period on public.payments(business_id,created_at);
create table public.audit_logs(id uuid primary key default gen_random_uuid(), business_id uuid references public.businesses(id), actor_id uuid, action text not null, details jsonb not null default '{}', created_at timestamptz not null default now());
create index audit_tenant on public.audit_logs(business_id,created_at);
create table public.invitations(id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id), email text not null, role text not null check(role in ('manager','staff','viewer')), token_hash text unique not null, expires_at timestamptz not null default now()+interval '72 hours', accepted_at timestamptz, created_by uuid not null);
create table public.subscription_invoices(id uuid primary key default gen_random_uuid(), subscription_id uuid not null references public.subscriptions(id), invoice_no bigint generated always as identity unique, amount_minor bigint not null check(amount_minor>0), due_at timestamptz not null, created_at timestamptz not null default now());
create table public.subscription_payments(id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.subscription_invoices(id), amount_minor bigint not null check(amount_minor>0), reference text not null unique, verified_by uuid not null references auth.users(id), created_at timestamptz not null default now());
create table public.support_tickets(id uuid primary key default gen_random_uuid(), business_id uuid references public.businesses(id), requester_id uuid, email text not null, topic text not null, message text not null, state text not null default 'open' check(state in ('open','assigned','resolved')), assigned_to uuid references public.platform_admins(user_id), resolution text, created_at timestamptz not null default now());
create table public.rate_limits(bucket text primary key, hits int not null default 1, expires_at timestamptz not null);
create table public.notifications(id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id), recipient_id uuid not null references auth.users(id), title text not null, href text not null, read_at timestamptz, created_at timestamptz not null default now());

create function public.member_role(b uuid) returns text language sql stable security definer set search_path=public,extensions,pg_temp as $$ select role from business_members where business_id=b and user_id=auth.uid() and active $$;
create function public.is_admin() returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select exists(select 1 from platform_admins where user_id=auth.uid() and active) and coalesce(auth.jwt()->>'aal','')='aal2' $$;
create function public.can_finance(b uuid) returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select coalesce(member_role(b) in ('owner','manager'),false) $$;
create function public.can_collect_payment(b uuid) returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select coalesce(can_finance(b) or exists(select 1 from business_members where business_id=b and user_id=auth.uid() and active and can_collect),false) $$;
create function public.assert_access(b uuid, roles text[], writing boolean default true) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
begin
 if not coalesce(member_role(b)=any(roles),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if writing and (not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null)) then raise exception 'Verify your email first' using errcode='42501'; end if;
 if writing and (not exists(select 1 from businesses where id=b and state='active') or not exists(select 1 from subscriptions where business_id=b and state in ('trialing','active','past_due','grace') and now() < period_end + case when state='trialing' then interval '0 days' else make_interval(days=>grace_days) end)) then raise exception 'Workspace is read only. Contact the owner about subscription renewal.' using errcode='42501'; end if;
end $$;
create function public.audit(b uuid,a text,d jsonb default '{}') returns void language sql security definer set search_path=public,extensions,pg_temp as $$ insert into audit_logs(business_id,actor_id,action,details) values(b,auth.uid(),a,d) $$;
create function public.enforce_limit(b uuid, kind text) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare lim int; used int;
begin
 perform 1 from businesses where id=b for update;
 if kind='branches' then select p.branches into lim from subscriptions s join plans p on p.id=s.plan_id where s.business_id=b; select count(*) into used from branches where business_id=b and active;
 elsif kind='resources' then select p.resources into lim from subscriptions s join plans p on p.id=s.plan_id where s.business_id=b; select count(*) into used from facilities where business_id=b and active;
 elsif kind='seats' then select p.seats into lim from subscriptions s join plans p on p.id=s.plan_id where s.business_id=b; select (select count(*) from business_members where business_id=b and active)+(select count(*) from invitations where business_id=b and accepted_at is null and expires_at>now()) into used;
 else raise exception 'Unknown limit'; end if;
 if lim is null or used>=lim then raise exception 'Plan % limit reached',kind; end if;
end $$;
create function public.validate_slot(b uuid,f uuid,s timestamptz,e timestamptz,guest boolean default false) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare r facilities; biz businesses; tz text; ls timestamp; le timestamp; mins int;
begin
 select * into r from facilities where business_id=b and id=f and active for update;
 if not found then raise exception 'Facility unavailable'; end if;
 select * into biz from businesses where id=b and state='active'; if not found then raise exception 'Business unavailable'; end if;
 select timezone into tz from branches where business_id=b and id=r.branch_id and active;
 if tz is null then raise exception 'Branch unavailable'; end if;
 ls:=s at time zone tz; le:=e at time zone tz; mins:=extract(epoch from e-s)::int/60;
 if e<=s or extract(epoch from e-s)::int%60<>0 or not(mins=any(r.durations)) or extract(minute from ls)::int%30<>0 or extract(second from ls)<>0 then raise exception 'Choose an allowed duration on the 30-minute grid'; end if;
 if ls::date<>le::date or not exists(select 1 from opening_hours where facility_id=f and weekday=extract(dow from ls) and opens<=ls::time and closes>=le::time) then raise exception 'Time is outside opening hours'; end if;
 if exists(select 1 from availability_exceptions where facility_id=f and starts_at<e+make_interval(mins=>r.buffer_minutes) and ends_at>s) then raise exception 'Facility is closed at this time'; end if;
 if guest and (not biz.published or not r.published or s<now()+make_interval(mins=>biz.lead_minutes) or s>now()+make_interval(days=>biz.horizon_days)) then raise exception 'Slot outside public booking rules'; end if;
 return jsonb_build_object('rate_minor',r.rate_minor,'duration_minutes',mins,'total_minor',(r.rate_minor*mins+30)/60,'buffer_minutes',r.buffer_minutes,'currency','BDT');
end $$;
create function public.create_booking(b uuid,d jsonb,guest boolean default false) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare q jsonb; result bookings; cid uuid; s timestamptz:=(d->>'starts_at')::timestamptz; e timestamptz:=(d->>'ends_at')::timestamptz; fid uuid:=(d->>'facility_id')::uuid; key uuid:=(d->>'idempotency_key')::uuid;
begin
 if guest then
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists(select 1 from subscriptions where business_id=b and state in ('trialing','active','past_due','grace') and now()<period_end+case when state='trialing' then interval '0 days' else make_interval(days=>grace_days) end) then raise exception 'Booking requests are unavailable'; end if;
 else perform assert_access(b,array['owner','manager','staff']); end if;
 perform pg_advisory_xact_lock(hashtextextended(b::text||key::text,0));
 select * into result from bookings where business_id=b and idempotency_key=key;
 if found then return jsonb_build_object('id',result.id,'ref',result.ref,'state',result.state,'total_minor',result.total_minor); end if;
 q:=validate_slot(b,fid,s,e,guest);
 if exists(select 1 from bookings where facility_id=fid and state in ('confirmed','checked_in','completed','no_show') and starts_at<e+make_interval(mins=>(q->>'buffer_minutes')::int) and occupied_until>s) then raise exception 'This time has just been booked. Choose another slot.' using errcode='23P01'; end if;
 insert into customers(business_id,name,phone,consent) values(b,d->>'customer_name',d->>'phone',coalesce((d->>'consent')::boolean,false)) on conflict(business_id,phone) do update set phone=excluded.phone returning id into cid;
 insert into bookings(business_id,facility_id,customer_id,starts_at,ends_at,occupied_until,state,source,total_minor,price_snapshot,notes,created_by,idempotency_key,expires_at)
 values(b,fid,cid,s,e,e+make_interval(mins=>(q->>'buffer_minutes')::int),case when guest then 'requested' else 'confirmed' end,case when guest then 'public' else coalesce(d->>'source','manual') end,(q->>'total_minor')::bigint,q,case when guest then '' else coalesce(d->>'notes','') end,auth.uid(),key,case when guest then least(s,now()+make_interval(hours=>(select request_expiry_hours from businesses where id=b))) end) returning * into result;
 insert into booking_events(business_id,booking_id,actor_id,action) values(b,result.id,auth.uid(),result.state);
 perform audit(b,'booking.created',jsonb_build_object('booking_id',result.id,'source',result.source));
 return jsonb_build_object('id',result.id,'ref',result.ref,'state',result.state,'total_minor',result.total_minor);
end $$;
create function public.change_booking(b uuid,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare r bookings; target text:=d->>'state'; q jsonb; s timestamptz; e timestamptz;
begin
 perform assert_access(b,array['owner','manager','staff']);
 select * into r from bookings where business_id=b and id=(d->>'id')::uuid for update;
 if not found then raise exception 'Booking not found'; end if;
 if r.version<>(d->>'version')::int then raise exception 'Booking changed. Refresh before retrying.'; end if;
 if target='reschedule' then
  if r.state<>'confirmed' then raise exception 'Only confirmed bookings can be rescheduled'; end if;
  s:=(d->>'starts_at')::timestamptz; e:=(d->>'ends_at')::timestamptz;
  if e-s<>r.ends_at-r.starts_at then raise exception 'Keep the original duration or create a new booking'; end if;
  q:=validate_slot(b,r.facility_id,s,e);
  update bookings set starts_at=s,ends_at=e,occupied_until=e+make_interval(mins=>(q->>'buffer_minutes')::int),version=version+1 where id=r.id;
 else
  if not ((r.state='requested' and target in ('confirmed','declined','expired')) or (r.state='confirmed' and target in ('checked_in','cancelled','no_show')) or (r.state='checked_in' and target in ('completed','cancelled'))) then raise exception 'Invalid booking transition'; end if;
  if target='confirmed' then
   if r.expires_at<=now() then raise exception 'Request expired'; end if;
   perform validate_slot(b,r.facility_id,r.starts_at,r.ends_at);
  end if;
  if target in ('cancelled','declined') and length(coalesce(d->>'reason',''))<3 then raise exception 'Provide a reason'; end if;
  update bookings set state=target,version=version+1 where id=r.id;
 end if;
 insert into booking_events(business_id,booking_id,actor_id,action,details) values(b,r.id,auth.uid(),target,jsonb_build_object('previous',r.state,'reason',d->>'reason','previous_start',r.starts_at));
 perform audit(b,'booking.'||target,jsonb_build_object('booking_id',r.id));
 return jsonb_build_object('id',r.id);
end $$;
create function public.record_payment(b uuid,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
create function public.onboard(d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare b uuid; plan uuid;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verified account required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if (select count(*) from business_members where user_id=auth.uid() and role='owner')>=5 then raise exception 'Workspace limit reached. Contact support.'; end if;
 select id into plan from plans where slug=coalesce(d->>'plan','starter') and published order by version desc limit 1;
 if plan is null then raise exception 'Plan unavailable'; end if;
 insert into businesses(slug,name,phone,city) values(d->>'slug',d->>'name',coalesce(d->>'phone',''),coalesce(d->>'city','')) returning id into b;
 insert into business_members(business_id,user_id,role,can_collect) values(b,auth.uid(),'owner',true);
 insert into subscriptions(business_id,plan_id) values(b,plan);
 perform audit(b,'workspace.created');
 return jsonb_build_object('id',b,'slug',d->>'slug');
end $$;
create function public.mutate(b uuid,action text,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
create function public.accept_invite(token text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare inv invitations; email text;
begin
 select lower(u.email) into email from auth.users u where id=auth.uid() and email_confirmed_at is not null;
 if email is null then raise exception 'Verify your invited email first'; end if;
 select * into inv from invitations where token_hash=encode(digest(token,'sha256'),'hex') and accepted_at is null and expires_at>now() for update;
 if not found or inv.email<>email then raise exception 'Invitation expired, used, or belongs to another email'; end if;
 perform 1 from businesses where id=inv.business_id for update;
 if exists(select 1 from business_members where business_id=inv.business_id and user_id=auth.uid()) then raise exception 'Already a member. Ask the owner to restore access.'; end if;
 -- The pending invitation already reserves one seat; serialize on business lock.
 insert into business_members(business_id,user_id,role) values(inv.business_id,auth.uid(),inv.role);
 update invitations set accepted_at=now() where id=inv.id;
 perform audit(inv.business_id,'team.accepted');
 return jsonb_build_object('slug',(select slug from businesses where id=inv.business_id));
end $$;
create function public.platform_mutate(action text,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
create function public.consume_rate(key text,maximum int,window_seconds int) returns boolean language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare n int;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Access denied'; end if;
 insert into rate_limits(bucket,hits,expires_at) values(key,1,now()+make_interval(secs=>window_seconds)) on conflict(bucket) do update set hits=case when rate_limits.expires_at<now() then 1 else rate_limits.hits+1 end,expires_at=case when rate_limits.expires_at<now() then excluded.expires_at else rate_limits.expires_at end returning hits into n;
 return n<=maximum;
end $$;
create function public.public_catalog(slug_value text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare b businesses;
begin
 select * into b from businesses where slug=slug_value and published and state='active';
 if not found then return null; end if;
 return jsonb_build_object('id',b.id,'name',b.name,'slug',b.slug,'city',b.city,'phone',b.public_phone,'lead_minutes',b.lead_minutes,'horizon_days',b.horizon_days,'facilities',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'sport',f.sport,'rate_minor',f.rate_minor,'durations',f.durations,'timezone',br.timezone,'address',br.address,'hours',(select jsonb_agg(jsonb_build_object('weekday',h.weekday,'opens',h.opens,'closes',h.closes)) from opening_hours h where h.facility_id=f.id))), '[]') from facilities f join branches br on br.id=f.branch_id where f.business_id=b.id and f.active and f.published and br.active));
end $$;
create function public.public_slots(slug_value text,fid uuid,day_value date,duration_value int) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare b businesses; r facilities; tz text; result jsonb:='[]'; h opening_hours; s timestamptz; e timestamptz; q jsonb;
begin
 select * into b from businesses where slug=slug_value and published and state='active';
 select * into r from facilities where id=fid and business_id=b.id and active and published;
 if r.id is null or not(duration_value=any(r.durations)) then raise exception 'Facility or duration unavailable'; end if;
 select timezone into tz from branches where id=r.branch_id and active;
 if tz is null then return result; end if;
 for h in select * from opening_hours where facility_id=fid and weekday=extract(dow from day_value) loop
  s:=(day_value+h.opens) at time zone tz;
  while s+make_interval(mins=>duration_value)<=((day_value+h.closes) at time zone tz) loop
   e:=s+make_interval(mins=>duration_value);
   begin
    q:=validate_slot(b.id,fid,s,e,true);
    if not exists(select 1 from bookings where facility_id=fid and state in ('confirmed','checked_in','completed','no_show') and starts_at<e+make_interval(mins=>r.buffer_minutes) and occupied_until>s) then result:=result||jsonb_build_array(jsonb_build_object('starts_at',s,'ends_at',e,'total_minor',q->'total_minor')); end if;
   exception when raise_exception then null;
   end;
   s:=s+interval '30 minutes';
  end loop;
 end loop;
 return result;
end $$;
create function public.guest_request(slug_value text,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare b uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Access denied'; end if;
 select id into b from businesses where slug=slug_value and published;
 if b is null then raise exception 'Business unavailable'; end if;
 return create_booking(b,d,true);
end $$;
create function public.guest_support(d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare rid uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Access denied'; end if;
 insert into support_tickets(email,topic,message) values(d->>'email',d->>'topic',d->>'message') returning id into rid;
 return jsonb_build_object('id',rid);
end $$;
-- Append-only ledgers, booking history and audits have no direct write grants.
do $$ declare t text; begin
 foreach t in array array['profiles','platform_admins','plans','plan_entitlements','businesses','business_members','subscriptions','branches','facilities','opening_hours','availability_exceptions','customers','customer_notes','bookings','booking_events','payments','audit_logs','invitations','subscription_invoices','subscription_payments','support_tickets','rate_limits','notifications'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['branches','facilities','opening_hours','availability_exceptions'] loop
  execute format('create policy tenant_read on public.%I for select to authenticated using (public.member_role(business_id) is not null)',t);
 end loop;
 foreach t in array array['customers','customer_notes','bookings','booking_events'] loop
  execute format('create policy operations_read on public.%I for select to authenticated using (public.member_role(business_id) in (''owner'',''manager'',''staff''))',t);
 end loop;
end $$;
create policy profile_self on profiles for select to authenticated using(user_id=auth.uid());
create policy admin_self on platform_admins for select to authenticated using(user_id=auth.uid());
create policy plans_read on plans for select to authenticated using(published or is_admin());
create policy entitlements_read on plan_entitlements for select to authenticated using(exists(select 1 from plans where id=plan_id));
create policy business_read on businesses for select to authenticated using(member_role(id) is not null or is_admin());
create policy member_read on business_members for select to authenticated using(user_id=auth.uid() or member_role(business_id) in ('owner','manager'));
create policy subscription_read on subscriptions for select to authenticated using(member_role(business_id)='owner' or is_admin());
create policy customer_notes_read on customer_notes for select to authenticated using(member_role(business_id) in ('owner','manager'));
create policy ledger_read on payments for select to authenticated using(can_finance(business_id));
create policy audit_read on audit_logs for select to authenticated using(member_role(business_id) in ('owner','manager') or (business_id is null and is_admin()));
create policy invite_read on invitations for select to authenticated using(member_role(business_id) in ('owner','manager'));
create policy invoice_read on subscription_invoices for select to authenticated using(exists(select 1 from subscriptions where id=subscription_id));
create policy saas_receipts_read on subscription_payments for select to authenticated using(exists(select 1 from subscription_invoices where id=invoice_id));
create policy support_read on support_tickets for select to authenticated using(member_role(business_id) in ('owner','manager') or requester_id=auth.uid() or is_admin());
create policy notification_read on notifications for select to authenticated using(recipient_id=auth.uid() and member_role(business_id) is not null);
-- Fail closed: explicitly expose only intended functions. Helpers callable by SQL owner only.
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.member_role(uuid),public.can_finance(uuid),public.can_collect_payment(uuid),public.is_admin() to authenticated;
grant execute on function public.onboard(jsonb),public.mutate(uuid,text,jsonb),public.create_booking(uuid,jsonb,boolean),public.change_booking(uuid,jsonb),public.record_payment(uuid,jsonb),public.accept_invite(text),public.platform_mutate(text,jsonb) to authenticated;
grant execute on function public.public_catalog(text),public.public_slots(text,uuid,date,int),public.guest_request(text,jsonb),public.guest_support(jsonb),public.consume_rate(text,int,int) to service_role;
-- No application service-role table reads/writes are used. Public access goes through allowlisted RPCs.
create function public.workspace_access(b uuid) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare writable boolean:=true;
begin
 perform assert_access(b,array['owner','manager','staff','viewer'],false);
 begin perform assert_access(b,array['owner','manager','staff']); exception when insufficient_privilege then writable:=false; end;
 return jsonb_build_object('writable',writable,'finance',can_finance(b),'collect',can_collect_payment(b));
end $$;
create function public.schedule(b uuid,s timestamptz,e timestamptz) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
begin
 perform assert_access(b,array['owner','manager','staff','viewer'],false);
 if e-s>interval '32 days' then raise exception 'Choose a range of 32 days or less'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'facility_id',facility_id,'starts_at',starts_at,'ends_at',ends_at,'state',state,'ref',ref)),'[]') from bookings where business_id=b and starts_at<e and ends_at>s and state in ('confirmed','checked_in','completed','no_show'));
end $$;
grant execute on function public.workspace_access(uuid),public.schedule(uuid,timestamptz,timestamptz) to authenticated;
revoke create on schema public from public,anon,authenticated;

create function public.published_plans() returns jsonb language sql stable security definer set search_path=public,extensions,pg_temp as $$ select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'name',name,'monthly_minor',monthly_minor,'branches',branches,'resources',resources,'seats',seats) order by monthly_minor),'[]') from plans where published $$;
grant execute on function public.published_plans() to anon,authenticated,service_role;
create function public.business_report(b uuid,from_at timestamptz,to_at timestamptz,branch uuid default null) returns jsonb language plpgsql stable security definer set search_path=public,extensions,pg_temp as $$
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
grant execute on function public.business_report(uuid,timestamptz,timestamptz,uuid) to authenticated;

create function public.booking_balance(b uuid,booking uuid) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare total bigint;net bigint;
begin
 perform assert_access(b,array['owner','manager','staff'],false);
 if not can_collect_payment(b) then raise exception 'Payment permission required'; end if;
 select total_minor into total from bookings where business_id=b and id=booking;
 if total is null then raise exception 'Booking not found'; end if;
 select coalesce(sum(case when kind='collection' then amount_minor else -amount_minor end),0) into net from payments where business_id=b and booking_id=booking;
 return jsonb_build_object('total_minor',total,'collected_minor',net,'due_minor',greatest(0,total-net));
end $$;
grant execute on function public.booking_balance(uuid,uuid) to authenticated;

create function public.refresh_subscription_states() returns int language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
grant execute on function public.refresh_subscription_states() to service_role;
