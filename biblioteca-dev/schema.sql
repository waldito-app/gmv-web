-- Biblioteca GMV: ejecutar únicamente en proyecto de pruebas tras revisión.
begin;
create schema if not exists gmv_library;
revoke all on schema gmv_library from public;
create table gmv_library.books (
 id uuid primary key default gen_random_uuid(), slug text unique not null,
 title text not null, description text not null default '',
 access_mode text not null check(access_mode in ('free','paid','academic','private')),
 published boolean not null default false, cover_url text,
 price_minor integer check(price_minor >= 0), currency text check(currency in ('UYU','USD')),
 isbn_digital text, isbn_paperback text, isbn_hardcover text,
 rights_cleared boolean not null default false,
 check(not published or rights_cleared),
 check(access_mode <> 'paid' or (price_minor is not null and price_minor > 0 and currency is not null))
);
create table gmv_library.chapters (
 book_id uuid references gmv_library.books on delete cascade, ordinal integer check(ordinal > 0),
 title text not null, body_text text not null, primary key(book_id,ordinal)
);
create table gmv_library.entitlements (
 user_id uuid references auth.users on delete cascade, book_id uuid references gmv_library.books on delete cascade,
 granted_at timestamptz not null default now(), expires_at timestamptz, revoked_at timestamptz,
 primary key(user_id,book_id)
);
alter table gmv_library.books enable row level security;
alter table gmv_library.chapters enable row level security;
alter table gmv_library.entitlements enable row level security;
-- No direct client grants. Public RPCs expose only intended fields.
create function public.gmv_catalog() returns table(id uuid,slug text,title text,description text,access_mode text,cover_url text,price_minor integer,currency text)
language sql stable security definer set search_path = '' as $$
 select b.id,b.slug,b.title,b.description,b.access_mode,b.cover_url,b.price_minor,b.currency
 from gmv_library.books b where b.published and b.rights_cleared and b.access_mode <> 'private' order by b.title;
$$;
create function public.gmv_my_books() returns table(id uuid,slug text,title text)
language sql stable security definer set search_path = '' as $$
 select b.id,b.slug,b.title from gmv_library.books b
 where auth.uid() is not null and b.published and b.rights_cleared and
 (b.access_mode='free' or exists(select 1 from gmv_library.entitlements e where e.book_id=b.id and e.user_id=auth.uid() and e.revoked_at is null and (e.expires_at is null or e.expires_at>now())));
$$;
create function public.gmv_chapter(p_book uuid,p_ordinal integer) returns table(title text,body_text text)
language sql stable security definer set search_path = '' as $$
 select c.title,c.body_text from gmv_library.chapters c join public.gmv_my_books() b on b.id=c.book_id
 where c.book_id=p_book and c.ordinal=p_ordinal;
$$;
create function public.gmv_toc(p_book uuid) returns table(ordinal integer,title text)
language sql stable security definer set search_path = '' as $$
 select c.ordinal,c.title from gmv_library.chapters c join public.gmv_my_books() b on b.id=c.book_id
 where c.book_id=p_book order by c.ordinal;
$$;
revoke all on function public.gmv_catalog() from public;
revoke all on function public.gmv_my_books() from public;
revoke all on function public.gmv_chapter(uuid,integer) from public;
revoke all on function public.gmv_toc(uuid) from public;
grant execute on function public.gmv_catalog() to anon,authenticated;
grant execute on function public.gmv_my_books(),public.gmv_chapter(uuid,integer),public.gmv_toc(uuid) to authenticated;
commit;
