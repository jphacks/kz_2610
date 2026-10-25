-- D1/SQLite. All access goes through the Worker; D1 has no Postgres RLS.
create table users (
  id text primary key not null,
  apple_subject text not null unique,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
create table auth_challenges (nonce_hash text primary key not null, expires_at integer not null);
create table sessions (
  token_hash text primary key not null,
  user_id text not null references users(id) on delete cascade,
  expires_at integer not null
);
create index sessions_expiry on sessions(expires_at);
create table profiles (
  id text primary key not null references users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 40),
  handle text not null unique check (length(handle) between 3 and 40 and handle not glob '*[^a-z0-9_.]*'),
  avatar_path text,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
create table profile_preferences (
  user_id text primary key not null references profiles(id) on delete cascade,
  allow_id_search integer not null check (allow_id_search in (0,1)) default false,
  show_visit_date integer not null check (show_visit_date in (0,1)) default true,
  include_in_friend_avg integer not null check (include_in_friend_avg in (0,1)) default true
);
create table friend_requests (
  id text primary key not null,
  from_id text not null references profiles(id) on delete cascade,
  to_id text not null references profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  unique(from_id, to_id), check (from_id <> to_id)
);
-- 一つの承認済みペアで双方向の関係を表現する。クライアントの直接書き込みは禁止。
create table friendships (
  user_low text not null references profiles(id) on delete cascade,
  user_high text not null references profiles(id) on delete cascade,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  primary key(user_low, user_high), check (user_low < user_high)
);
create table favorite_friends (
  user_id text not null references profiles(id) on delete cascade,
  friend_id text not null references profiles(id) on delete cascade,
  primary key(user_id, friend_id), check (user_id <> friend_id)
);
create table blocks (
  blocker_id text not null references profiles(id) on delete cascade,
  blocked_id text not null references profiles(id) on delete cascade,
  primary key(blocker_id, blocked_id), check (blocker_id <> blocked_id)
);
create table restaurants (
  id text primary key not null,
  external_key text not null unique check (length(external_key) between 1 and 300),
  name text not null check (length(name) between 1 and 200),
  category text,
  address text not null default '' check (length(address) <= 500),
  latitude real not null check (latitude between -90 and 90),
  longitude real not null check (longitude between -180 and 180),
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
create table reviews (
  id text primary key not null,
  user_id text not null  references profiles(id) on delete cascade,
  restaurant_id text not null references restaurants(id),
  rating real not null check (rating between 1 and 5 and rating * 2 = cast(rating * 2 as integer)),
  comment text not null default '' check (length(comment) <= 300),
  dish text not null default '' check (length(dish) <= 100),
  want_again integer not null check (want_again in (0,1)) default false,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  unique(user_id, restaurant_id), unique(id, user_id)
);
-- 来店日は元テーブルから友達に漏れないよう分離し、設定に従うRPC経由でのみ返す。
create table review_visits (
  review_id text primary key not null,
  user_id text not null,
  visited_on text not null,
  foreign key(review_id, user_id) references reviews(id, user_id) on delete cascade
);
create table review_photos (
  id text primary key not null,
  review_id text not null,
  user_id text not null,
  slot integer not null check (slot between 1 and 5),
  object_path text generated always as (user_id || '/' || review_id || '/' || id || '.jpg') stored unique,
  foreign key(review_id, user_id) references reviews(id, user_id) on delete cascade,
  unique(review_id, slot)
);
create table saved_restaurants (
  user_id text not null  references profiles(id) on delete cascade,
  restaurant_id text not null references restaurants(id),
  status text check (status in ('want_to_go','visited')),
  is_favorite integer not null check (is_favorite in (0,1)) default false,
  saved_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  primary key(user_id, restaurant_id), check (status is not null or is_favorite)
);

create index friend_requests_recipient on friend_requests(to_id, status);
create index friendships_high on friendships(user_high);
create index blocks_reverse on blocks(blocked_id, blocker_id);
create index reviews_restaurant on reviews(restaurant_id);
create index restaurants_coordinates on restaurants(latitude, longitude);


-- Enforce relationship invariants within the writing statement, including races.
create trigger request_insert_guard before insert on friend_requests begin
  select case when
    exists(select 1 from blocks where (blocker_id=new.from_id and blocked_id=new.to_id) or (blocker_id=new.to_id and blocked_id=new.from_id))
    or exists(select 1 from friendships where user_low=min(new.from_id,new.to_id) and user_high=max(new.from_id,new.to_id))
    or exists(select 1 from friend_requests where from_id=new.to_id and to_id=new.from_id and status='pending')
    or not exists(select 1 from profile_preferences where user_id=new.to_id and allow_id_search=1)
    then raise(abort,'request_not_allowed') end;
end;
create trigger request_update_guard before update on friend_requests begin
  select case when new.from_id<>old.from_id or new.to_id<>old.to_id
    or exists(select 1 from blocks where (blocker_id=new.from_id and blocked_id=new.to_id) or (blocker_id=new.to_id and blocked_id=new.from_id))
    or (new.status in ('accepted','declined') and old.status<>'pending')
    then raise(abort,'request_not_allowed') end;
end;
create trigger request_accepted after update of status on friend_requests when new.status='accepted' begin
  insert into friendships(user_low,user_high) values(min(new.from_id,new.to_id),max(new.from_id,new.to_id)) on conflict do nothing;
end;
create trigger friendship_removed after delete on friendships begin
  delete from favorite_friends where (user_id=old.user_low and friend_id=old.user_high) or (user_id=old.user_high and friend_id=old.user_low);
  delete from friend_requests where (from_id=old.user_low and to_id=old.user_high) or (from_id=old.user_high and to_id=old.user_low);
end;
create trigger user_blocked after insert on blocks begin
  delete from friendships where user_low=min(new.blocker_id,new.blocked_id) and user_high=max(new.blocker_id,new.blocked_id);
  delete from favorite_friends where (user_id=new.blocker_id and friend_id=new.blocked_id) or (user_id=new.blocked_id and friend_id=new.blocker_id);
  delete from friend_requests where (from_id=new.blocker_id and to_id=new.blocked_id) or (from_id=new.blocked_id and to_id=new.blocker_id);
end;
create trigger favorite_guard before insert on favorite_friends begin
  select case when not exists(select 1 from friendships where user_low=min(new.user_id,new.friend_id) and user_high=max(new.user_id,new.friend_id))
    or exists(select 1 from blocks where (blocker_id=new.user_id and blocked_id=new.friend_id) or (blocker_id=new.friend_id and blocked_id=new.user_id))
    then raise(abort,'friend_required') end;
end;
create trigger review_inserted after insert on reviews begin
  insert into saved_restaurants(user_id,restaurant_id,status) values(new.user_id,new.restaurant_id,'visited')
    on conflict(user_id,restaurant_id) do update set status='visited';
end;
create trigger review_updated after update of rating, comment, dish, want_again on reviews begin
  update reviews set updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') where id=new.id;
  insert into saved_restaurants(user_id,restaurant_id,status) values(new.user_id,new.restaurant_id,'visited')
    on conflict(user_id,restaurant_id) do update set status='visited';
end;
