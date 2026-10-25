-- 「行きたい」：いいね（端末内）・保存一覧（saved_restaurants）とは別に持つ。本人だけが読み書きできる。
create table want_to_go (
  user_id text not null references profiles(id) on delete cascade,
  restaurant_id text not null references restaurants(id),
  added_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  primary key(user_id, restaurant_id)
);
-- 行きたいはレビューを書いた（行った）ら外れる。
create trigger want_to_go_reviewed after insert on reviews begin
  delete from want_to_go where user_id=new.user_id and restaurant_id=new.restaurant_id;
end;
create trigger want_to_go_review_updated after update of rating, comment, dish, want_again on reviews begin
  delete from want_to_go where user_id=new.user_id and restaurant_id=new.restaurant_id;
end;
