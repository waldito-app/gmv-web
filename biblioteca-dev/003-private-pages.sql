-- 003: private page assets; apply only to isolated Supabase test project.
begin;
insert into storage.buckets(id,name,public) values ('gmv-private-pages','gmv-private-pages',false)
on conflict(id) do nothing;
do $$ begin
 if exists(select 1 from storage.buckets where id='gmv-private-pages' and public) then
 raise exception 'GMV bucket must be private'; end if;
end $$;
create table gmv_library.pages (
 book_id uuid not null references gmv_library.books on delete cascade,
 ordinal integer not null check(ordinal>0),
 object_name text not null unique,
 width_px integer not null check(width_px>0),
 height_px integer not null check(height_px>0),
 primary key(book_id,ordinal),
 check(object_name = book_id::text || '/' || ordinal::text || '.webp')
);
alter table gmv_library.pages enable row level security;
create function public.gmv_page_manifest(p_book uuid)
returns table(ordinal integer,width_px integer,height_px integer)
language sql stable security definer set search_path='' as $$
 select p.ordinal,p.width_px,p.height_px from gmv_library.pages p
 join public.gmv_my_books() b on b.id=p.book_id
 where p.book_id=p_book order by p.ordinal;
$$;
create function public.gmv_can_read_page(p_name text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from gmv_library.pages p join public.gmv_my_books() b on b.id=p.book_id where p.object_name=p_name);
$$;
revoke all on function public.gmv_page_manifest(uuid),public.gmv_can_read_page(text) from public,anon;
grant execute on function public.gmv_page_manifest(uuid),public.gmv_can_read_page(text) to authenticated;
-- Restrictive guard prevents existing permissive policies from bypassing GMV authorization.
create policy gmv_pages_guard on storage.objects as restrictive for select to public
using (bucket_id <> 'gmv-private-pages' or (auth.uid() is not null and public.gmv_can_read_page(name)));
-- Grant only authenticated readers with current entitlement.
create policy gmv_pages_read on storage.objects for select to authenticated
using (bucket_id='gmv-private-pages' and public.gmv_can_read_page(name));
-- Block client writes even if unrelated permissive policies exist.
create policy gmv_pages_no_insert on storage.objects as restrictive for insert to public
with check (bucket_id <> 'gmv-private-pages');
create policy gmv_pages_no_update on storage.objects as restrictive for update to public
using (bucket_id <> 'gmv-private-pages') with check (bucket_id <> 'gmv-private-pages');
create policy gmv_pages_no_delete on storage.objects as restrictive for delete to public
using (bucket_id <> 'gmv-private-pages');
commit;
-- Trusted importer uses service role only outside browser. Never store source PDFs here.
-- Test anonymous, free, paid, academic, private, expired/revoked, unpublished and cross-book access.
-- Use authenticated download, not public URLs; signed URLs remain usable until expiry.
