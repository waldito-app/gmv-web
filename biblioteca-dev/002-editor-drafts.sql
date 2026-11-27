-- GMV: migración 002, solo entorno de pruebas, después de schema.sql.
begin;
create table gmv_library.editors (
 user_id uuid primary key references auth.users on delete cascade
);
alter table gmv_library.editors enable row level security;
create function public.gmv_is_editor() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from gmv_library.editors e where e.user_id=auth.uid());
$$;
create function public.gmv_editor_save_draft(p_slug text,p_title text,p_description text,p_mode text,p_cover text,p_price integer,p_currency text,p_chapters jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare bid uuid; n integer;
begin
 if not public.gmv_is_editor() then raise exception 'Forbidden' using errcode='42501'; end if;
 if p_slug is null or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or nullif(trim(p_title),'') is null then raise exception 'Invalid metadata'; end if;
 if jsonb_typeof(p_chapters) is distinct from 'array' then raise exception 'Invalid chapters'; end if;
 n:=jsonb_array_length(p_chapters);
 if n<1 or n>500 or octet_length(p_chapters::text)>10000000 then raise exception 'Invalid manuscript size'; end if;
 if exists(select 1 from jsonb_array_elements(p_chapters) c where jsonb_typeof(c) is distinct from 'object' or nullif(trim(c->>'title'),'') is null or nullif(trim(c->>'body_text'),'') is null) then raise exception 'Empty chapter'; end if;
 insert into gmv_library.books(slug,title,description,access_mode,cover_url,price_minor,currency)
 values(p_slug,p_title,coalesce(p_description,''),p_mode,p_cover,p_price,p_currency)
 on conflict(slug) do update set title=excluded.title,description=excluded.description,access_mode=excluded.access_mode,cover_url=excluded.cover_url,price_minor=excluded.price_minor,currency=excluded.currency,rights_cleared=false
 where not books.published returning id into bid;
 if bid is null then raise exception 'Published book cannot be overwritten'; end if;
 delete from gmv_library.chapters where book_id=bid;
 insert into gmv_library.chapters(book_id,ordinal,title,body_text)
 select bid, ord::integer,c->>'title',c->>'body_text' from jsonb_array_elements(p_chapters) with ordinality as a(c,ord);
 return bid;
end; $$;
revoke all on function public.gmv_is_editor() from public;
revoke all on function public.gmv_editor_save_draft(text,text,text,text,text,integer,text,jsonb) from public;
grant execute on function public.gmv_is_editor(),public.gmv_editor_save_draft(text,text,text,text,text,integer,text,jsonb) to authenticated;
commit;
-- Bootstrap editor only via trusted SQL administrator using verified auth.users UUID.
-- No browser-side role assignment, publication or rights clearance in this migration.
