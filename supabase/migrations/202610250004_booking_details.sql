-- Adds audited, version-checked correction of booking source and internal notes.
-- Safe to replay after 202610250003_supabase_extensions.sql.
begin;
create or replace function public.change_booking(b uuid,d jsonb) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare r bookings; target text:=d->>'state'; q jsonb; s timestamptz; e timestamptz; new_source text; new_notes text;
begin
 perform assert_access(b,array['owner','manager','staff']);
 select * into r from bookings where business_id=b and id=(d->>'id')::uuid for update;
 if not found then raise exception 'Booking not found'; end if;
 if r.version<>(d->>'version')::int then raise exception 'Booking changed. Refresh before retrying.'; end if;
 if target='edit_details' then
  new_source:=coalesce(d->>'source',''); new_notes:=coalesce(d->>'notes','');
  if (r.source='public' and new_source<>'public') or (r.source<>'public' and new_source not in ('manual','phone','whatsapp')) then raise exception 'Invalid booking source'; end if;
  if length(new_notes)>2000 then raise exception 'Notes are too long'; end if;
  if r.source is distinct from new_source or r.notes is distinct from new_notes then
   update bookings set source=new_source,notes=new_notes,version=version+1 where id=r.id;
   insert into booking_events(business_id,booking_id,actor_id,action,details) values(b,r.id,auth.uid(),'details_edited',jsonb_build_object('source_before',r.source,'source_after',new_source,'notes_changed',r.notes is distinct from new_notes));
   perform audit(b,'booking.details_edited',jsonb_build_object('booking_id',r.id,'source_changed',r.source is distinct from new_source,'notes_changed',r.notes is distinct from new_notes));
  end if;
  return jsonb_build_object('id',r.id);
 end if;
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
revoke all on function public.change_booking(uuid,jsonb) from public,anon;
grant execute on function public.change_booking(uuid,jsonb) to authenticated;
commit;
