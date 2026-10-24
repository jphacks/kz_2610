begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  handle text not null unique check (handle ~ '^[a-z0-9_.]{3,40}$'),
  avatar_path text,
  created_at timestamptz not null default now()
);
create table public.profile_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  allow_id_search boolean not null default false,
  show_visit_date boolean not null default true,
  include_in_friend_avg boolean not null default true
);
create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  unique(from_id, to_id), check (from_id <> to_id)
);
-- 一つの承認済みペアで双方向の関係を表現する。クライアントの直接書き込みは禁止。
create table public.friendships (
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_low, user_high), check (user_low < user_high)
);
create table public.favorite_friends (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  primary key(user_id, friend_id), check (user_id <> friend_id)
);
create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  primary key(blocker_id, blocked_id), check (blocker_id <> blocked_id)
);
create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  external_key text not null unique check (char_length(external_key) between 1 and 300),
  name text not null check (char_length(name) between 1 and 200),
  category text,
  address text not null default '' check (char_length(address) <= 500),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  created_at timestamptz not null default now()
);
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id),
  rating numeric not null check (rating between 1 and 5 and rating * 2 = floor(rating * 2)),
  comment text not null default '' check (char_length(comment) <= 300),
  dish text not null default '' check (char_length(dish) <= 100),
  want_again boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, restaurant_id), unique(id, user_id)
);
-- 来店日は元テーブルから友達に漏れないよう分離し、設定に従うRPC経由でのみ返す。
create table public.review_visits (
  review_id uuid primary key,
  user_id uuid not null,
  visited_on date not null,
  foreign key(review_id, user_id) references public.reviews(id, user_id) on delete cascade
);
create table public.review_photos (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null,
  user_id uuid not null,
  slot smallint not null check (slot between 1 and 5),
  object_path text generated always as (user_id::text || '/' || review_id::text || '/' || id::text || '.jpg') stored unique,
  foreign key(review_id, user_id) references public.reviews(id, user_id) on delete cascade,
  unique(review_id, slot)
);
create table public.saved_restaurants (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id),
  status text check (status in ('want_to_go','visited')),
  is_favorite boolean not null default false,
  saved_at timestamptz not null default now(),
  primary key(user_id, restaurant_id), check (status is not null or is_favorite)
);

create index friend_requests_recipient on public.friend_requests(to_id, status);
create index friendships_high on public.friendships(user_high);
create index blocks_reverse on public.blocks(blocked_id, blocker_id);
create index reviews_restaurant on public.reviews(restaurant_id);
create index restaurants_coordinates on public.restaurants(latitude, longitude);

create function private.blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.blocks where
    (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;
create function private.connected(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select a is not null and b is not null and not private.blocked(a,b) and exists(
    select 1 from public.friendships where user_low = least(a,b) and user_high = greatest(a,b));
$$;
create function private.can_read_review(owner_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (owner_id = auth.uid() or private.connected(auth.uid(), owner_id));
$$;
create function private.can_read_profile(owner_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (owner_id = auth.uid() or
    (not private.blocked(auth.uid(), owner_id) and (
      private.connected(auth.uid(), owner_id) or
      exists(select 1 from public.profile_preferences where user_id = owner_id and allow_id_search) or
      exists(select 1 from public.friend_requests where status = 'pending' and
        ((from_id = auth.uid() and to_id = owner_id) or (to_id = auth.uid() and from_id = owner_id)))
    )));
$$;
create function private.is_friend(other_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.connected(auth.uid(), other_id);
$$;
create function private.can_read_photo(path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.review_photos p where p.object_path = path and private.can_read_review(p.user_id));
$$;
create function private.can_write_photo(path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.review_photos p where p.object_path = path and p.user_id = auth.uid());
$$;

create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name, handle)
    values(new.id, 'ユーザー', 'u_' || replace(new.id::text, '-', ''));
  insert into public.profile_preferences(user_id) values(new.id);
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();
insert into public.profiles(id,display_name,handle)
  select id,'ユーザー','u_' || replace(id::text,'-','') from auth.users on conflict(id) do nothing;
insert into public.profile_preferences(user_id)
  select id from public.profiles on conflict(user_id) do nothing;

create function private.review_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'UPDATE' then new.updated_at = now(); end if;
  insert into public.saved_restaurants(user_id, restaurant_id, status)
    values(new.user_id, new.restaurant_id, 'visited')
    on conflict(user_id, restaurant_id) do update set status = 'visited';
  return new;
end;
$$;
create trigger review_marks_visited before insert or update on public.reviews
  for each row execute function private.review_changed();

alter table public.profiles enable row level security;
alter table public.profile_preferences enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.favorite_friends enable row level security;
alter table public.blocks enable row level security;
alter table public.restaurants enable row level security;
alter table public.reviews enable row level security;
alter table public.review_visits enable row level security;
alter table public.review_photos enable row level security;
alter table public.saved_restaurants enable row level security;

create policy profiles_read on public.profiles for select to authenticated using(private.can_read_profile(id));
create policy profiles_update on public.profiles for update to authenticated using(id = (select auth.uid())) with check(id = (select auth.uid()));
create policy preferences_owner on public.profile_preferences for all to authenticated using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
create policy requests_participants on public.friend_requests for select to authenticated
  using((from_id = (select auth.uid()) or to_id = (select auth.uid())) and not private.blocked(from_id, to_id));
create policy friendships_participants on public.friendships for select to authenticated
  using(user_low = (select auth.uid()) or user_high = (select auth.uid()));
create policy favorites_read on public.favorite_friends for select to authenticated using(user_id = (select auth.uid()));
create policy favorites_insert on public.favorite_friends for insert to authenticated with check(user_id = (select auth.uid()) and private.is_friend(friend_id));
create policy favorites_delete on public.favorite_friends for delete to authenticated using(user_id = (select auth.uid()));
create policy blocks_owner on public.blocks for select to authenticated using(blocker_id = (select auth.uid()));
create policy restaurants_read on public.restaurants for select to anon, authenticated using(true);
create policy restaurants_insert on public.restaurants for insert to authenticated with check(true);
create policy reviews_read on public.reviews for select to authenticated using(private.can_read_review(user_id));
create policy reviews_insert on public.reviews for insert to authenticated with check(user_id = (select auth.uid()));
create policy reviews_update on public.reviews for update to authenticated using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
create policy reviews_delete on public.reviews for delete to authenticated using(user_id = (select auth.uid()));
create policy visits_owner on public.review_visits for all to authenticated using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
create policy photos_read on public.review_photos for select to authenticated using(private.can_read_review(user_id));
create policy photos_insert on public.review_photos for insert to authenticated with check(user_id = (select auth.uid()));
create policy photos_delete on public.review_photos for delete to authenticated using(user_id = (select auth.uid()));
create policy saved_owner on public.saved_restaurants for all to authenticated using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));

revoke all on public.profiles, public.profile_preferences, public.friend_requests, public.friendships,
  public.favorite_friends, public.blocks, public.restaurants, public.reviews, public.review_visits,
  public.review_photos, public.saved_restaurants from public, anon, authenticated;
grant select on public.restaurants to anon;
grant select on public.profiles, public.profile_preferences, public.friend_requests, public.friendships,
  public.favorite_friends, public.blocks, public.restaurants, public.reviews, public.review_visits,
  public.review_photos, public.saved_restaurants to authenticated;
grant update(display_name, handle, avatar_path) on public.profiles to authenticated;
grant update(allow_id_search, show_visit_date, include_in_friend_avg) on public.profile_preferences to authenticated;
grant insert, delete on public.favorite_friends to authenticated;
grant insert on public.restaurants to authenticated;
grant insert(id, user_id, restaurant_id, rating, comment, dish, want_again) on public.reviews to authenticated;
grant update(rating, comment, dish, want_again), delete on public.reviews to authenticated;
grant insert, update, delete on public.review_visits, public.saved_restaurants to authenticated;
grant insert, delete on public.review_photos to authenticated;
grant all on public.profiles, public.profile_preferences, public.friend_requests, public.friendships,
  public.favorite_friends, public.blocks, public.restaurants, public.reviews, public.review_visits,
  public.review_photos, public.saved_restaurants to service_role;

-- ペア単位のロックで、承認・削除・ブロックの同時実行を直列化する。
create function private.lock_pair(a uuid, b uuid) returns void
language sql volatile set search_path = '' as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(a,b)::text || greatest(a,b)::text, 0));
$$;

create function public.send_friend_request(target_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); result uuid;
begin
  if actor is null or target_id is null or actor = target_id then raise exception 'invalid_request'; end if;
  perform private.lock_pair(actor, target_id);
  if not private.can_read_profile(target_id) or private.blocked(actor,target_id) or private.connected(actor,target_id) then
    raise exception 'request_not_allowed';
  end if;
  if exists(select 1 from public.friend_requests where from_id = target_id and to_id = actor and status = 'pending') then
    raise exception 'respond_to_incoming_request';
  end if;
  insert into public.friend_requests(from_id,to_id) values(actor,target_id)
    on conflict(from_id,to_id) do update set status = 'pending', created_at = now() returning id into result;
  return result;
end;
$$;
create function public.respond_friend_request(request_id uuid, accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare req public.friend_requests; actor uuid := auth.uid();
begin
  select * into req from public.friend_requests where id = request_id;
  if not found or actor is null or actor <> req.to_id or accept is null then raise exception 'request_not_allowed'; end if;
  perform private.lock_pair(req.from_id,req.to_id);
  select * into req from public.friend_requests where id = request_id for update;
  if not found or req.status <> 'pending' or private.blocked(req.from_id,req.to_id) then raise exception 'request_not_allowed'; end if;
  update public.friend_requests set status = case when accept then 'accepted' else 'declined' end where id = request_id;
  if accept then
    insert into public.friendships(user_low,user_high) values(least(req.from_id,req.to_id),greatest(req.from_id,req.to_id)) on conflict do nothing;
  end if;
end;
$$;
create function public.cancel_friend_request(request_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare req public.friend_requests; actor uuid := auth.uid();
begin
  select * into req from public.friend_requests where id = request_id;
  if not found or actor is null or actor <> req.from_id then raise exception 'request_not_allowed'; end if;
  perform private.lock_pair(req.from_id,req.to_id);
  delete from public.friend_requests where id = request_id and from_id = actor and status = 'pending';
end;
$$;
create function public.remove_friend(other_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or other_id is null or actor = other_id then raise exception 'invalid_user'; end if;
  perform private.lock_pair(actor,other_id);
  delete from public.friendships where user_low = least(actor,other_id) and user_high = greatest(actor,other_id);
  delete from public.favorite_friends where (user_id = actor and friend_id = other_id) or (user_id = other_id and friend_id = actor);
  delete from public.friend_requests where (from_id = actor and to_id = other_id) or (from_id = other_id and to_id = actor);
end;
$$;
create function public.block_user(other_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or other_id is null or actor = other_id then raise exception 'invalid_user'; end if;
  perform private.lock_pair(actor,other_id);
  insert into public.blocks(blocker_id,blocked_id) values(actor,other_id) on conflict do nothing;
  delete from public.friendships where user_low = least(actor,other_id) and user_high = greatest(actor,other_id);
  delete from public.favorite_friends where (user_id = actor and friend_id = other_id) or (user_id = other_id and friend_id = actor);
  delete from public.friend_requests where (from_id = actor and to_id = other_id) or (from_id = other_id and to_id = actor);
end;
$$;
create function public.unblock_user(other_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  perform private.lock_pair(auth.uid(),other_id);
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = other_id;
end;
$$;

create function public.friend_ratings(friend_ids uuid[], min_lat double precision, min_lng double precision,
                                     max_lat double precision, max_lng double precision)
returns table(restaurant_id uuid, average_rating numeric, friend_count bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if min_lat is null or max_lat is null or min_lng is null or max_lng is null or
     not (min_lat between -90 and 90 and max_lat between -90 and 90 and min_lat <= max_lat and
          min_lng between -180 and 180 and max_lng between -180 and 180 and min_lng <= max_lng) then
    raise exception 'invalid_bounds';
  end if;
  return query select r.restaurant_id, avg(r.rating), count(*) from public.reviews r
    join public.restaurants p on p.id = r.restaurant_id
    join public.profile_preferences pref on pref.user_id = r.user_id
    where private.connected(auth.uid(),r.user_id) and pref.include_in_friend_avg
      and (friend_ids is null or r.user_id = any(friend_ids))
      and p.latitude between min_lat and max_lat and p.longitude between min_lng and max_lng
    group by r.restaurant_id order by r.restaurant_id limit 1000;
end;
$$;
create function public.friend_review_details(target_restaurant uuid)
returns table(id uuid, user_id uuid, rating numeric, comment text, dish text, want_again boolean, visited_on date, updated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select r.id,r.user_id,r.rating,r.comment,r.dish,r.want_again,
    case when r.user_id = auth.uid() or pref.show_visit_date then v.visited_on else null end, r.updated_at
  from public.reviews r join public.profile_preferences pref on pref.user_id = r.user_id
    left join public.review_visits v on v.review_id = r.id
  where r.restaurant_id = target_restaurant and private.can_read_review(r.user_id)
  order by r.updated_at desc, r.id limit 1000;
$$;

-- レビュー本体・来店日・行ったへの移動を一つのトランザクションで更新する。
create function public.save_my_review(target_restaurant uuid, new_rating numeric, new_comment text default '',
                                     new_dish text default '', new_want_again boolean default false, new_visited_on date default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare result_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  insert into public.reviews(user_id,restaurant_id,rating,comment,dish,want_again)
    values(auth.uid(),target_restaurant,new_rating,new_comment,new_dish,new_want_again)
    on conflict(user_id,restaurant_id) do update set
      rating = excluded.rating, comment = excluded.comment, dish = excluded.dish, want_again = excluded.want_again
    returning id into result_id;
  if new_visited_on is null then
    delete from public.review_visits v where v.review_id = result_id and v.user_id = auth.uid();
  else
    insert into public.review_visits(review_id,user_id,visited_on) values(result_id,auth.uid(),new_visited_on)
      on conflict(review_id) do update set visited_on = excluded.visited_on;
  end if;
  return result_id;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.can_read_review(uuid), private.can_read_profile(uuid), private.is_friend(uuid),
  private.blocked(uuid,uuid), private.can_read_photo(text), private.can_write_photo(text) to authenticated;
revoke all on function public.send_friend_request(uuid), public.respond_friend_request(uuid,boolean),
  public.cancel_friend_request(uuid), public.remove_friend(uuid), public.block_user(uuid), public.unblock_user(uuid),
  public.friend_ratings(uuid[],double precision,double precision,double precision,double precision),
  public.friend_review_details(uuid), public.save_my_review(uuid,numeric,text,text,boolean,date) from public, anon, authenticated;
grant execute on function public.send_friend_request(uuid), public.respond_friend_request(uuid,boolean),
  public.cancel_friend_request(uuid), public.remove_friend(uuid), public.block_user(uuid), public.unblock_user(uuid),
  public.friend_ratings(uuid[],double precision,double precision,double precision,double precision),
  public.friend_review_details(uuid), public.save_my_review(uuid,numeric,text,text,boolean,date) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('review-photos','review-photos',false,5242880,array['image/jpeg']);
create policy review_objects_read on storage.objects for select to authenticated
  using(bucket_id = 'review-photos' and (private.can_read_photo(name) or (storage.foldername(name))[1] = (select auth.uid())::text));
create policy review_objects_insert on storage.objects for insert to authenticated
  with check(bucket_id = 'review-photos' and private.can_write_photo(name));
-- レビュー削除後の孤立ファイルも本人がStorage API経由で削除できる。
create policy review_objects_delete on storage.objects for delete to authenticated
  using(bucket_id = 'review-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;
