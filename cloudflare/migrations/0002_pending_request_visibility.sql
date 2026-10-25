-- Match profile visibility when an already-pending recipient opts out of ID search.
-- New requests to hidden profiles remain forbidden.
drop trigger request_insert_guard;
create trigger request_insert_guard before insert on friend_requests begin
  select case when
    exists(select 1 from blocks where (blocker_id=new.from_id and blocked_id=new.to_id) or (blocker_id=new.to_id and blocked_id=new.from_id))
    or exists(select 1 from friendships where user_low=min(new.from_id,new.to_id) and user_high=max(new.from_id,new.to_id))
    or exists(select 1 from friend_requests where from_id=new.to_id and to_id=new.from_id and status='pending')
    or (not exists(select 1 from profile_preferences where user_id=new.to_id and allow_id_search=1)
      and not exists(select 1 from friend_requests where from_id=new.from_id and to_id=new.to_id and status='pending'))
    then raise(abort,'request_not_allowed') end;
end;
