-- Supabase installs pgcrypto in its trusted extensions schema. Keep pg_temp last.
begin;
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef loop
  execute format('alter function %s set search_path to public, extensions, pg_temp',f.signature);
 end loop;
end $$;
commit;
