-- Hackathon build: guest accounts replace Sign in with Apple.
-- Guests use 'guest:<user id>' as their subject; the column stays unique.
alter table users rename column apple_subject to auth_subject;
drop table auth_challenges;
