import { before, after, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { Miniflare } from "miniflare";
import worker from "../src/index.js";
import { hash, now } from "../src/auth.js";

// Synthetic identities only; ephemeral local D1 and R2, no production credentials.
const A = "00000000-0000-0000-0000-000000000001";
const B = "00000000-0000-0000-0000-000000000002";
const C = "00000000-0000-0000-0000-000000000003";
const tokens = {
  [A]: "a".repeat(64),
  [B]: "b".repeat(64),
  [C]: "c".repeat(64),
};
const bounds = "min_lat=34&min_lng=138&max_lat=37&max_lng=141";
let mf, db, env, shop, review, photo;
const sql = (s, ...args) => db.prepare(s).bind(...args);
async function api(actor, method, path, value, extra = {}) {
  const headers = { ...extra };
  if (actor) headers.Authorization = `Bearer ${tokens[actor] ?? actor}`;
  let payload = value;
  if (value !== undefined && !(value instanceof Uint8Array)) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(value);
  }
  return worker.fetch(
    new Request(`https://api.example.test/v1${path}`, {
      method,
      headers,
      body: payload,
    }),
    env,
  );
}
async function data(actor, method, path, value, status = 200) {
  const response = await api(actor, method, path, value);
  const result = await response.json();
  assert.equal(response.status, status, JSON.stringify(result));
  return result;
}
async function connect() {
  const { id } = await data(A, "POST", "/requests", { target_id: B }, 201);
  await data(B, "PATCH", `/requests/${id}`, { accept: true });
  return id;
}
before(async () => {
  mf = new Miniflare({
    modules: true,
    script: 'export default {fetch(){return new Response("test harness")}}',
    compatibilityDate: "2026-07-30",
    d1Databases: ["DB"],
    r2Buckets: ["PHOTOS"],
  });
  db = await mf.getD1Database("DB");
  env = {
    DB: db,
    PHOTOS: await mf.getR2Bucket("PHOTOS"),
    AUTH_RATE_LIMITER: { limit: async () => ({ success: true }) },
  };
  // exec() splits lines; prepare().run() supports complete triggers with semicolons.
  const directory = new URL("../migrations/", import.meta.url);
  for (const name of (await readdir(directory))
    .filter((name) => name.endsWith(".sql"))
    .sort()) {
    const migration = await readFile(new URL(name, directory), "utf8");
    const statements = migration.match(
      /create trigger[\s\S]*?\nend;|(?:--[^\n]*\n|\s)*(?:create table|create index|drop trigger|drop table|alter table)[\s\S]*?;/gi,
    );
    assert.ok(statements?.length, `No SQL found in ${name}`);
    for (const statement of statements) await db.prepare(statement).run();
  }
});
after(async () => {
  await mf?.dispose();
});
beforeEach(async () => {
  await db.batch(
    [
      "delete from users",
      "delete from restaurants",
    ].map((s) => db.prepare(s)),
  );
  for (const actor of [A, B, C]) {
    await db.batch([
      sql(
        "insert into users(id,auth_subject) values(?,?)",
        actor,
        `synthetic:${actor}`,
      ),
      sql(
        "insert into profiles(id,display_name,handle) values(?,?,?)",
        actor,
        "架空ユーザー",
        `test_${actor.slice(-1)}`,
      ),
      sql(
        "insert into profile_preferences(user_id,allow_id_search) values(?,?)",
        actor,
        actor === B ? 1 : 0,
      ),
      sql(
        "insert into sessions(token_hash,user_id,expires_at) values(?,?,?)",
        await hash(tokens[actor]),
        actor,
        now() + 3600,
      ),
    ]);
  }
  shop = await data(
    B,
    "POST",
    "/restaurants",
    {
      external_key: "fixture:restaurant",
      name: "架空の食堂",
      latitude: 35,
      longitude: 139,
    },
    201,
  );
  review = await data(B, "PUT", "/reviews", {
    restaurant_id: shop.id,
    rating: 4.5,
    visited_on: "2026-10-24",
  });
  photo = await data(
    B,
    "POST",
    "/photos",
    { review_id: review.id, slot: 1 },
    201,
  );
});

test("anonymous/forged/expired sessions cannot access private routes", async () => {
  for (const actor of [null, "0".repeat(64), "bad-token"])
    await data(actor, "GET", "/me", undefined, 401);
  await sql(
    "update sessions set expires_at=? where user_id=?",
    now() - 1,
    A,
  ).run();
  await data(A, "GET", "/me", undefined, 401);
  assert.equal((await data(null, "GET", `/restaurants?${bounds}`)).length, 1);
  await data(null, "GET", "/restaurants", undefined, 400);
});
test("owners see their data while outsiders and pending requesters cannot", async () => {
  assert.equal(
    (await data(B, "GET", `/reviews?restaurant_id=${shop.id}`)).length,
    1,
  );
  assert.equal(
    (await data(A, "GET", `/reviews?restaurant_id=${shop.id}`)).length,
    0,
  );
  assert.equal(
    (await data(A, "GET", `/photos?review_id=${review.id}`)).length,
    0,
  );
  const req = await data(A, "POST", "/requests", { target_id: B }, 201);
  await data(A, "PATCH", `/requests/${req.id}`, { accept: true }, 404);
  await data(C, "PATCH", `/requests/${req.id}`, { accept: true }, 404);
  assert.equal(
    (await data(A, "GET", `/reviews?restaurant_id=${shop.id}`)).length,
    0,
  );
  await data(B, "PATCH", `/requests/${req.id}`, { accept: true });
  assert.equal(
    (await data(A, "GET", `/reviews?restaurant_id=${shop.id}`)).length,
    1,
  );
  assert.equal((await data(A, "GET", "/saved")).length, 0);
});
test("blocking immediately revokes profiles, reviews, ratings and photos in both directions", async () => {
  await connect();
  await data(A, "PUT", `/friends/${B}/favorite`, {});
  const jpeg = new Uint8Array([255, 216, 255, 217]);
  assert.equal(
    (
      await api(B, "PUT", `/objects/${photo.object_path}`, jpeg, {
        "Content-Type": "image/jpeg",
      })
    ).status,
    200,
  );
  const visible = await api(A, "GET", `/objects/${photo.object_path}`);
  assert.equal(visible.status, 200);
  assert.equal(visible.headers.get("Cache-Control"), "private, no-store");
  await visible.arrayBuffer();
  assert.equal(
    (await data(A, "GET", `/ratings?${bounds}`))[0].average_rating,
    4.5,
  );
  await data(A, "PUT", `/blocks/${B}`, {});
  await data(A, "GET", `/profiles/${B}`, undefined, 404);
  await data(B, "GET", `/profiles/${A}`, undefined, 404);
  await data(A, "GET", `/objects/${photo.object_path}`, undefined, 404);
  assert.equal(
    (await data(A, "GET", `/reviews?restaurant_id=${shop.id}`)).length,
    0,
  );
  assert.equal((await data(A, "GET", `/ratings?${bounds}`)).length, 0);
  assert.equal((await data(A, "GET", "/friends")).length, 0);
  await data(B, "POST", "/requests", { target_id: A }, 409);
  await data(A, "DELETE", `/blocks/${B}`);
  assert.equal((await data(A, "GET", "/friends")).length, 0);
});
test("stale acceptance, reciprocal requests and self relationships are rejected", async () => {
  const req = await data(A, "POST", "/requests", { target_id: B }, 201);
  await data(B, "POST", "/requests", { target_id: A }, 409);
  await data(B, "PUT", `/blocks/${A}`, {});
  await data(B, "PATCH", `/requests/${req.id}`, { accept: true }, 404);
  await data(A, "POST", "/requests", { target_id: A }, 400);
  assert.equal((await data(A, "GET", "/friends")).length, 0);
});
test("concurrent block and acceptance never leave a friendship or favorites", async () => {
  const req = await data(A, "POST", "/requests", { target_id: B }, 201);
  const responses = await Promise.all([
    api(B, "PATCH", `/requests/${req.id}`, { accept: true }),
    api(A, "PUT", `/blocks/${B}`, {}),
  ]);
  assert.ok([200, 404, 409].includes(responses[0].status));
  assert.equal(responses[1].status, 200);
  for (const response of responses) await response.arrayBuffer();
  assert.equal((await data(A, "GET", "/friends")).length, 0);
  assert.equal(
    (await sql("select * from friendships").all()).results.length,
    0,
  );
});
test("removal cleans favorites and requests; unfriend revokes photo metadata", async () => {
  await data(A, "PUT", `/friends/${B}/favorite`, {}, 409);
  await connect();
  await data(A, "PUT", `/friends/${B}/favorite`, {});
  assert.equal((await data(A, "GET", "/friends"))[0].is_favorite, 1);
  assert.equal((await data(B, "GET", "/friends"))[0].is_favorite, 0);
  await data(A, "DELETE", `/friends/${B}`);
  assert.equal(
    (await data(A, "GET", `/photos?review_id=${review.id}`)).length,
    0,
  );
  assert.equal((await data(A, "GET", "/requests")).length, 0);
});
test("profile search is opt-in, exact, and ignores caller-supplied owner IDs", async () => {
  assert.equal((await data(A, "GET", "/profiles?handle=test_3")).length, 0);
  assert.equal((await data(A, "GET", "/profiles?handle=test_2")).length, 1);
  await data(A, "PUT", "/preferences", {
    user_id: C,
    allow_id_search: true,
    show_visit_date: false,
    include_in_friend_avg: false,
  });
  assert.equal((await data(C, "GET", "/preferences")).allow_id_search, 0);
  assert.equal((await data(A, "GET", "/preferences")).show_visit_date, 0);
  await data(A, "PATCH", "/me", {
    id: C,
    display_name: "架空A",
    handle: "fixture_a",
  });
  assert.equal((await data(C, "GET", "/me")).handle, "test_3");
});
test("hidden visit dates and aggregate opt-out are enforced; friend filters cannot include strangers", async () => {
  await connect();
  assert.equal(
    (await data(A, "GET", `/reviews?restaurant_id=${shop.id}`))[0].visited_on,
    "2026-10-24",
  );
  await data(B, "PUT", "/preferences", {
    allow_id_search: true,
    show_visit_date: false,
    include_in_friend_avg: false,
  });
  assert.equal(
    (await data(A, "GET", `/reviews?restaurant_id=${shop.id}`))[0].visited_on,
    null,
  );
  assert.equal(
    (await data(B, "GET", `/reviews?restaurant_id=${shop.id}`))[0].visited_on,
    "2026-10-24",
  );
  assert.equal((await data(A, "GET", `/ratings?${bounds}`)).length, 0);
  await data(B, "PUT", "/preferences", {
    allow_id_search: true,
    show_visit_date: true,
    include_in_friend_avg: true,
  });
  assert.equal(
    (await data(A, "GET", `/ratings?${bounds}&friend_ids=`)).length,
    0,
  );
  assert.equal(
    (await data(A, "GET", `/ratings?${bounds}&friend_ids=${C}`)).length,
    0,
  );
  assert.equal(
    (await data(A, "GET", `/ratings?${bounds}&friend_ids=${B},${B}`))[0]
      .friend_count,
    1,
  );
});
test("review upsert preserves ID, atomically marks visited and keeps favorites", async () => {
  await data(A, "PUT", `/saved/${shop.id}`, {
    status: "want_to_go",
    is_favorite: true,
  });
  const first = await data(A, "PUT", "/reviews", {
    user_id: B,
    restaurant_id: shop.id,
    rating: 5,
    visited_on: "2026-10-25",
  });
  const next = await data(A, "PUT", "/reviews", {
    restaurant_id: shop.id,
    rating: 4.5,
  });
  assert.equal(first.id, next.id);
  const saved = await data(A, "GET", "/saved");
  assert.equal(saved[0].status, "visited");
  assert.equal(saved[0].is_favorite, 1);
  assert.equal((await data(A, "GET", "/me/reviews"))[0].visited_on, null);
  await data(A, "DELETE", `/reviews/${review.id}`, undefined, 404);
  await data(A, "DELETE", `/reviews/${first.id}`);
  assert.equal((await data(A, "GET", "/saved"))[0].status, "visited");
});
test("invalid ratings, unicode lengths, invalid dates and bounds leave existing data intact", async () => {
  for (const rating of [0, 4.01, 4.2, 5.5, "5"])
    await data(B, "PUT", "/reviews", { restaurant_id: shop.id, rating }, 400);
  await data(
    B,
    "PUT",
    "/reviews",
    { restaurant_id: shop.id, rating: 5, comment: "あ".repeat(301) },
    400,
  );
  await data(
    B,
    "PUT",
    "/reviews",
    { restaurant_id: shop.id, rating: 5, visited_on: "2026-02-30" },
    400,
  );
  await data(
    B,
    "PUT",
    "/reviews",
    { restaurant_id: shop.id, rating: 5, want_again: 1 },
    400,
  );
  await data(
    A,
    "GET",
    "/ratings?min_lat=50&max_lat=30&min_lng=0&max_lng=1",
    undefined,
    400,
  );
  const rows = await data(B, "GET", "/me/reviews");
  assert.equal(rows[0].rating, 4.5);
  assert.equal(rows[0].visited_on, "2026-10-24");
});
test("photo slots enforce five maximum and owner-reserved object paths", async () => {
  for (let slot = 2; slot <= 5; slot++)
    await data(B, "POST", "/photos", { review_id: review.id, slot }, 201);
  await data(B, "POST", "/photos", { review_id: review.id, slot: 6 }, 400);
  await data(B, "POST", "/photos", { review_id: review.id, slot: 1 }, 409);
  await data(A, "POST", "/photos", { review_id: review.id, slot: 1 }, 404);
  const jpeg = new Uint8Array([255, 216, 255, 217]);
  assert.equal(
    (
      await api(A, "PUT", `/objects/${photo.object_path}`, jpeg, {
        "Content-Type": "image/jpeg",
      })
    ).status,
    404,
  );
  assert.equal(
    (
      await api(B, "PUT", `/objects/${photo.object_path}`, jpeg, {
        "Content-Type": "image/png",
      })
    ).status,
    415,
  );
  assert.equal(
    (
      await api(
        B,
        "PUT",
        `/objects/${photo.object_path}`,
        new Uint8Array([1, 2, 3, 4]),
        { "Content-Type": "image/jpeg" },
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await api(
        B,
        "PUT",
        `/objects/${photo.object_path}`,
        new Uint8Array(5242881),
        { "Content-Type": "image/jpeg" },
      )
    ).status,
    413,
  );
});
test("deleted reviews hide objects from friends and permit owner cleanup after cascade", async () => {
  await connect();
  const jpeg = new Uint8Array([255, 216, 255, 217]);
  await (
    await api(B, "PUT", `/objects/${photo.object_path}`, jpeg, {
      "Content-Type": "image/jpeg",
    })
  ).arrayBuffer();
  await data(B, "DELETE", `/reviews/${review.id}`);
  await data(A, "GET", `/objects/${photo.object_path}`, undefined, 404);
  await data(A, "DELETE", `/objects/${photo.object_path}`, undefined, 404);
  await data(B, "DELETE", `/objects/${photo.object_path}`);
  assert.equal(await env.PHOTOS.get(photo.object_path), null);
});
test("request cancel is sender-only; decline creates no friendship; retries reuse request ID", async () => {
  const req = await data(A, "POST", "/requests", { target_id: B }, 201);
  await data(B, "DELETE", `/requests/${req.id}`, undefined, 404);
  await data(B, "PATCH", `/requests/${req.id}`, { accept: false });
  assert.equal((await data(A, "GET", "/friends")).length, 0);
  const retry = await data(A, "POST", "/requests", { target_id: B }, 201);
  assert.equal(req.id, retry.id);
  await data(A, "DELETE", `/requests/${req.id}`);
});
test("logout revokes session; errors omit raw database and user input", async () => {
  await data(A, "DELETE", "/auth/session");
  await data(A, "GET", "/me", undefined, 401);
  const response = await api(B, "POST", "/photos", {
    review_id: review.id,
    slot: 1,
  });
  assert.deepEqual(await response.json(), { error: "conflict" });
});
test("guest sign-up stores only hashed session and is searchable by its handle", async () => {
  const guest = await data(null, "POST", "/auth/guest", { display_name: " はなこ " }, 201);
  assert.match(guest.access_token, /^[a-f0-9]{64}$/);
  const row = await sql(
    "select token_hash from sessions where user_id=?",
    guest.user_id,
  ).first();
  assert.equal(row.token_hash, await hash(guest.access_token));
  const me = await data(guest.access_token, "GET", "/me");
  assert.equal(me.id, guest.user_id);
  assert.equal(me.display_name, "はなこ");
  assert.match(me.handle, /^[a-z2-9]{7}$/);
  const [found] = await data(A, "GET", `/profiles?handle=${me.handle}`);
  assert.equal(found.id, guest.user_id);
  const unnamed = await data(null, "POST", "/auth/guest", {}, 201);
  assert.notEqual(unnamed.user_id, guest.user_id);
  assert.equal((await data(unnamed.access_token, "GET", "/me")).display_name, "ゲスト");
  await data(null, "POST", "/auth/guest", { display_name: "あ".repeat(41) }, 400);
});
test("friend reviews list only connected friends with restaurant and author names", async () => {
  assert.deepEqual(await data(A, "GET", "/friend-reviews"), []);
  const [pending] = await data(B, "GET", "/requests");
  assert.equal(pending, undefined);
  const { id } = await data(A, "POST", "/requests", { target_id: B }, 201);
  const [incoming] = await data(B, "GET", "/requests");
  assert.equal(incoming.from_name, "架空ユーザー");
  assert.equal(incoming.from_handle, "test_1");
  await data(B, "PATCH", `/requests/${id}`, { accept: true });
  const [item] = await data(A, "GET", "/friend-reviews");
  assert.equal(item.user_id, B);
  assert.equal(item.display_name, "架空ユーザー");
  assert.equal(item.external_key, "fixture:restaurant");
  assert.equal(item.rating, 4.5);
  assert.equal(item.visited_on, undefined);
  assert.deepEqual(await data(B, "GET", "/friend-reviews"), []);
  await data(C, "GET", "/friend-reviews").then((rows) => assert.deepEqual(rows, []));
});

test("pending profiles stay visible after search opt-out; new hidden requests stay forbidden", async () => {
  const request = await data(A, "POST", "/requests", { target_id: B }, 201);
  await data(B, "PUT", "/preferences", {
    allow_id_search: false,
    show_visit_date: true,
    include_in_friend_avg: true,
  });
  assert.equal((await data(A, "GET", `/profiles/${B}`)).id, B);
  const retry = await data(A, "POST", "/requests", { target_id: B }, 201);
  assert.equal(retry.id, request.id);
  await data(C, "POST", "/requests", { target_id: B }, 409);
  await data(B, "PATCH", `/requests/${request.id}`, { accept: true });
  assert.equal((await data(A, "GET", "/friends")).length, 1);
});
test("auth rate limit rejects guest sign-up before creating users", async () => {
  const previous = env.AUTH_RATE_LIMITER;
  env.AUTH_RATE_LIMITER = { limit: async () => ({ success: false }) };
  try {
    await data(null, "POST", "/auth/guest", {}, 429);
    assert.equal(
      (await sql("select * from users").all()).results.length,
      3,
    );
  } finally {
    env.AUTH_RATE_LIMITER = previous;
  }
});
test("want-to-go is owner-only, separate from saved, keeps its date and clears on review", async () => {
  const other = await data(
    A,
    "POST",
    "/restaurants",
    {
      external_key: "fixture:want",
      name: "架空の喫茶",
      category: "MKPOICategoryCafe",
      latitude: 35.1,
      longitude: 139.1,
    },
    201,
  );
  await data(A, "PUT", `/want-to-go/${other.id}`);
  await data(A, "PUT", `/want-to-go/${shop.id}`);
  const first = await data(A, "GET", "/want-to-go");
  assert.equal(first.length, 2);
  const cafe = first.find((row) => row.restaurant_id === other.id);
  assert.equal(cafe.external_key, "fixture:want");
  assert.equal(cafe.name, "架空の喫茶");
  assert.equal(cafe.category, "MKPOICategoryCafe");
  // Re-adding keeps the original timestamp; saved/likes stay untouched.
  await data(A, "PUT", `/want-to-go/${other.id}`);
  const again = await data(A, "GET", "/want-to-go");
  assert.equal(
    again.find((row) => row.restaurant_id === other.id).added_at,
    cafe.added_at,
  );
  assert.equal((await data(A, "GET", "/saved")).length, 0);
  // Other users cannot see or remove it.
  assert.equal((await data(B, "GET", "/want-to-go")).length, 0);
  await data(B, "DELETE", `/want-to-go/${other.id}`);
  assert.equal((await data(A, "GET", "/want-to-go")).length, 2);
  // Writing a review (visited) removes the restaurant from want-to-go.
  await data(A, "PUT", "/reviews", { restaurant_id: shop.id, rating: 4 });
  const afterReview = await data(A, "GET", "/want-to-go");
  assert.deepEqual(
    afterReview.map((row) => row.restaurant_id),
    [other.id],
  );
  await data(A, "DELETE", `/want-to-go/${other.id}`);
  assert.equal((await data(A, "GET", "/want-to-go")).length, 0);
});
test("want-to-go rejects unknown restaurants, malformed IDs and anonymous callers", async () => {
  await data(A, "PUT", `/want-to-go/${"0".repeat(8)}-0000-0000-0000-${"0".repeat(12)}`, undefined, 404);
  await data(A, "PUT", "/want-to-go/not-a-uuid", undefined, 400);
  const anonymous = await api(null, "GET", "/want-to-go");
  assert.equal(anonymous.status, 401);
});
