import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, afterEach, test } from 'node:test';
import assert from 'node:assert/strict';

let db;
const A = '00000000-0000-0000-0000-000000000001';
const B = '00000000-0000-0000-0000-000000000002';
const C = '00000000-0000-0000-0000-000000000003';
const shop = '10000000-0000-0000-0000-000000000001';
const otherShop = '10000000-0000-0000-0000-000000000002';
const reviewB = '20000000-0000-0000-0000-000000000002';
const photoB = '30000000-0000-0000-0000-000000000002';
const pathB = `${B}/${reviewB}/${photoB}.jpg`;

before(async () => {
  db = new PGlite();
  await db.exec(await readFile(new URL('./bootstrap.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261024000100_initial_schema.sql', import.meta.url), 'utf8'));
});
after(async () => { await db?.close(); });
beforeEach(async () => {
  await db.exec('begin');
  await db.query('insert into auth.users(id) values($1),($2),($3)', [A, B, C]);
  await db.query('update public.profile_preferences set allow_id_search=true where user_id=$1', [B]);
  await db.query(`insert into public.restaurants(id,external_key,name,latitude,longitude)
    values($1,'test:one','架空の食堂',35,139),($2,'test:two','別の架空店舗',36,140)`, [shop, otherShop]);
  await db.query('insert into public.reviews(id,user_id,restaurant_id,rating) values($1,$2,$3,4.5)', [reviewB, B, shop]);
  await db.query('insert into public.review_visits(review_id,user_id,visited_on) values($1,$2,$3)', [reviewB, B, '2026-10-24']);
  await db.query('insert into public.review_photos(id,review_id,user_id,slot) values($1,$2,$3,1)', [photoB, reviewB, B]);
  await db.query("insert into storage.objects(bucket_id,name) values('review-photos',$1)", [pathB]);
});
afterEach(async () => { await db.exec('rollback'); await db.exec('reset role'); });

async function as(user, role = 'authenticated') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,true)", [user ?? '']);
  assert.ok(['authenticated', 'anon'].includes(role));
  await db.exec(`set local role ${role}`);
}
async function denied(sql, params = [], code = '42501') {
  await db.exec('savepoint expected_denial');
  let error;
  try { await db.query(sql, params); } catch (caught) { error = caught; }
  await db.exec('rollback to savepoint expected_denial; release savepoint expected_denial');
  assert.ok(error, 'Expected the database to reject this statement');
  assert.equal(error.code, code);
}
async function count(table, where = '', params = []) {
  return Number((await db.query(`select count(*) as n from ${table} ${where}`, params)).rows[0].n);
}
async function connectAB() {
  await as(A);
  const id = (await db.query('select public.send_friend_request($1) as id', [B])).rows[0].id;
  await as(B);
  await db.query('select public.respond_friend_request($1,true)', [id]);
  await as(A);
  return id;
}
async function ratings(ids = null) {
  return (await db.query('select * from public.friend_ratings($1,34,138,37,141)', [ids])).rows;
}

test('anonymous and unauthenticated contexts cannot read private data or invoke relationship RPCs', async () => {
  await as(null, 'anon');
  await denied('select * from public.reviews');
  await denied('select public.send_friend_request($1)', [B]);
  assert.equal(await count('storage.objects'), 0);
  assert.equal(await count('public.restaurants'), 2);
  await as(null);
  assert.equal(await count('public.reviews'), 0);
  await denied('select public.send_friend_request($1)', [B], 'P0001');
});

test('owners can read their reviews, dates, saved places and photos; outsiders cannot', async () => {
  await as(B);
  for (const table of ['public.reviews', 'public.review_visits', 'public.saved_restaurants', 'public.review_photos', 'storage.objects']) {
    assert.equal(await count(table), 1);
  }
  await as(A);
  for (const table of ['public.reviews', 'public.review_visits', 'public.saved_restaurants', 'public.review_photos', 'storage.objects']) {
    assert.equal(await count(table), 0);
  }
});

test('pending requests do not expose reviews, and only the recipient can accept', async () => {
  await as(A);
  const id = (await db.query('select public.send_friend_request($1) as id', [B])).rows[0].id;
  assert.equal(await count('public.reviews'), 0);
  await denied('select public.respond_friend_request($1,true)', [id], 'P0001');
  await as(C);
  await denied('select public.respond_friend_request($1,true)', [id], 'P0001');
  await as(B);
  await db.query('select public.respond_friend_request($1,true)', [id]);
  await as(A);
  assert.equal(await count('public.reviews'), 1);
  assert.equal(await count('public.review_photos'), 1);
  assert.equal(await count('storage.objects'), 1);
  assert.equal(await count('public.saved_restaurants'), 0);
});

test('users cannot create friendships directly, spoof authors, or modify someone else\'s review', async () => {
  await as(A);
  await denied('insert into public.friendships(user_low,user_high) values($1,$2)', [A, B]);
  await denied('insert into public.reviews(user_id,restaurant_id,rating) values($1,$2,5)', [B, otherShop]);
  assert.equal((await db.query('update public.reviews set rating=1 where id=$1 returning id', [reviewB])).rows.length, 0);
  assert.equal((await db.query('delete from public.reviews where id=$1 returning id', [reviewB])).rows.length, 0);
  await as(B);
  await denied('update public.reviews set user_id=$1 where id=$2', [A, reviewB]);
});

test('friend removal revokes reviews and photo access in the same transaction', async () => {
  await connectAB();
  await db.query('select public.remove_friend($1)', [B]);
  assert.equal(await count('public.reviews'), 0);
  assert.equal(await count('storage.objects'), 0);
  assert.equal(await count('public.review_photos'), 0);
  assert.equal((await ratings()).length, 0);
});

test('blocking revokes access both ways; unblocking does not recreate friendship', async () => {
  await connectAB();
  await db.query('select public.block_user($1)', [B]);
  assert.equal(await count('public.reviews'), 0);
  assert.equal(await count('storage.objects'), 0);
  assert.equal(await count('public.profiles', 'where id=$1', [B]), 0);
  await as(B);
  assert.equal(await count('public.profiles', 'where id=$1', [A]), 0);
  await denied('select public.send_friend_request($1)', [A], 'P0001');
  await as(A);
  await db.query('select public.unblock_user($1)', [B]);
  assert.equal(await count('public.reviews'), 0);
  assert.equal(await count('public.friendships'), 0);
});

test('blocking a pending requester prevents acceptance with a stale request id', async () => {
  await as(A);
  const id = (await db.query('select public.send_friend_request($1) as id', [B])).rows[0].id;
  await as(B);
  await db.query('select public.block_user($1)', [A]);
  await denied('select public.respond_friend_request($1,true)', [id], 'P0001');
  assert.equal(await count('public.friendships'), 0);
});

test('Friend Lens cannot include strangers, empty selections or excluded map ratings', async () => {
  await connectAB();
  assert.equal(Number((await ratings())[0].average_rating), 4.5);
  assert.equal(Number((await ratings())[0].friend_count), 1);
  assert.equal((await ratings([C])).length, 0);
  assert.equal((await ratings([])).length, 0);
  await as(B);
  await db.query('update public.profile_preferences set include_in_friend_avg=false where user_id=$1', [B]);
  await as(A);
  assert.equal((await ratings()).length, 0);
});

test('visit dates are private in the table and redacted by the friend detail RPC', async () => {
  await connectAB();
  assert.equal(await count('public.review_visits'), 0);
  assert.ok((await db.query('select * from public.friend_review_details($1)', [shop])).rows[0].visited_on);
  await as(B);
  await db.query('update public.profile_preferences set show_visit_date=false where user_id=$1', [B]);
  await as(A);
  assert.equal((await db.query('select * from public.friend_review_details($1)', [shop])).rows[0].visited_on, null);
});

test('profiles respect search opt-in and preferences are readable and writable only by the owner', async () => {
  await as(A);
  assert.equal(await count('public.profiles', 'where id=$1', [C]), 0);
  assert.equal(await count('public.profiles', 'where id=$1', [B]), 1);
  assert.equal(await count('public.profile_preferences'), 1);
  assert.equal((await db.query('update public.profile_preferences set allow_id_search=true where user_id=$1 returning user_id', [C])).rows.length, 0);
});

test('ratings must be exact half stars, comments are bounded, and a second review is rejected', async () => {
  await as(A);
  for (const value of [0, 0.5, 4.01, 4.2, 5.5]) {
    await denied('insert into public.reviews(restaurant_id,rating) values($1,$2)', [shop, value], '23514');
  }
  await denied('insert into public.reviews(restaurant_id,rating,comment) values($1,5,$2)', [shop, 'あ'.repeat(301)], '23514');
  await db.query('insert into public.reviews(restaurant_id,rating) values($1,4.5)', [shop]);
  await denied('insert into public.reviews(restaurant_id,rating) values($1,5)', [shop], '23505');
});

test('review posting atomically marks visited and retains favorites', async () => {
  await as(A);
  await db.query("insert into public.saved_restaurants(restaurant_id,status,is_favorite) values($1,'want_to_go',true)", [shop]);
  await db.query('insert into public.reviews(restaurant_id,rating) values($1,5)', [shop]);
  const entry = (await db.query('select * from public.saved_restaurants')).rows[0];
  assert.equal(entry.status, 'visited');
  assert.equal(entry.is_favorite, true);
  await denied("update public.saved_restaurants set user_id=$1 where restaurant_id=$2", [B, shop]);
});

test('photo slots cap metadata at five and uploads require the owner\'s reserved path', async () => {
  await as(B);
  for (let slot = 2; slot <= 5; slot++) {
    await db.query('insert into public.review_photos(review_id,user_id,slot) values($1,$2,$3)', [reviewB, B, slot]);
  }
  await denied('insert into public.review_photos(review_id,user_id,slot) values($1,$2,6)', [reviewB, B], '23514');
  await denied('insert into public.review_photos(review_id,user_id,slot) values($1,$2,1)', [reviewB, B], '23505');
  await denied("insert into storage.objects(bucket_id,name) values('review-photos',$1)", [`${B}/${reviewB}/not-reserved.jpg`]);
  await db.query('delete from public.review_photos where review_id=$1 and slot=5', [reviewB]);
  await as(A);
  await denied("insert into storage.objects(bucket_id,name) values('review-photos',$1)", [pathB]);
  await denied('insert into public.review_photos(review_id,user_id,slot) values($1,$2,5)', [reviewB, A], '23503');
});

test('deleted reviews hide their photos from friends while the owner can clean up the orphan', async () => {
  await connectAB();
  await as(B);
  await db.query('delete from public.reviews where id=$1', [reviewB]);
  await as(A);
  assert.equal(await count('storage.objects'), 0);
  await as(B);
  assert.equal((await db.query('delete from storage.objects where name=$1 returning id', [pathB])).rows.length, 1);
});

test('save_my_review updates the same review, visit date and visited state atomically', async () => {
  await as(A);
  const first = (await db.query("select public.save_my_review($1,4.5,'一回目','料理',true,'2026-10-24') as id", [shop])).rows[0].id;
  const second = (await db.query("select public.save_my_review($1,5,'更新','',false,null) as id", [shop])).rows[0].id;
  assert.equal(first, second);
  assert.equal(await count('public.reviews'), 1);
  assert.equal(Number((await db.query('select rating from public.reviews')).rows[0].rating), 5);
  assert.equal(await count('public.review_visits'), 0);
  assert.equal((await db.query('select status from public.saved_restaurants')).rows[0].status, 'visited');
});

test('invalid review RPC input rolls back without changing the old review or visit date', async () => {
  await as(B);
  await denied("select public.save_my_review($1,4.1,'bad','',false,null)", [shop], '23514');
  assert.equal(Number((await db.query('select rating from public.reviews')).rows[0].rating), 4.5);
  assert.equal(await count('public.review_visits'), 1);
});

test('favorite friends are private and require an accepted relationship', async () => {
  await as(A);
  await denied('insert into public.favorite_friends(user_id,friend_id) values($1,$2)', [A, B]);
  await connectAB();
  await db.query('insert into public.favorite_friends(user_id,friend_id) values($1,$2)', [A, B]);
  assert.equal(await count('public.favorite_friends'), 1);
  await as(B);
  assert.equal(await count('public.favorite_friends'), 0);
  await db.query('select public.remove_friend($1)', [A]);
  await as(A);
  assert.equal(await count('public.favorite_friends'), 0);
});

test('only the sender can cancel and a declined request does not create a friendship', async () => {
  await as(A);
  const first = (await db.query('select public.send_friend_request($1) as id', [B])).rows[0].id;
  await as(B);
  await denied('select public.cancel_friend_request($1)', [first], 'P0001');
  await db.query('select public.respond_friend_request($1,false)', [first]);
  assert.equal(await count('public.friendships'), 0);
  await as(A);
  const next = (await db.query('select public.send_friend_request($1) as id', [B])).rows[0].id;
  await db.query('select public.cancel_friend_request($1)', [next]);
  assert.equal(await count('public.friend_requests'), 0);
});
