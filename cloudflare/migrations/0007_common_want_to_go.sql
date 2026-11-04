-- 両者が明示的にオンにしたときだけ、共通のお店を返す。
alter table profile_preferences add column share_want_to_go integer not null default 0 check (share_want_to_go in (0,1));
