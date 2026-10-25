alter table profiles add column bio text not null default '' check(length(bio)<=160);
alter table profiles add column avatar_symbol text not null default 'person.fill';
alter table restaurants add column google_place_id text;
create unique index restaurants_place_id on restaurants(google_place_id);
create table recovery_keys (
  user_id text primary key references users(id) on delete cascade,
  key_hash text not null unique
);
create table library_backups (
  user_id text primary key references users(id) on delete cascade,
  version integer not null default 0,
  payload text not null,
  updated_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
create table maintenance_state (id integer primary key, payload text not null);
