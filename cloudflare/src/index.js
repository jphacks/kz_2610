import { findRestaurantPhoto, HotPepperError } from "./hotpepper.js";
import { hash, now, randomToken, verifyAppleIdentity } from "./auth.js";

const MAX_PHOTO = 5 * 1024 * 1024;
const uuid = (value) =>
  typeof value === "string" &&
  /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value);
const fail = (status, code) => {
  throw new APIError(status, code);
};
class APIError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}
const json = (value, status = 200) =>
  Response.json(value, {
    status,
    headers: {
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
const text = (value, max, min = 0) => {
  if (
    typeof value !== "string" ||
    [...value].length < min ||
    [...value].length > max
  )
    fail(400, "invalid_text");
  return value;
};
const bool = (value) => {
  if (typeof value !== "boolean") fail(400, "invalid_boolean");
  return Number(value);
};
const id = (value) => {
  if (!uuid(value)) fail(400, "invalid_id");
  return value;
};
const number = (value, min, max) => {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < min ||
    value > max
  )
    fail(400, "invalid_number");
  return value;
};
async function bytes(request, limit) {
  const reader = request.body?.getReader();
  if (!reader) fail(400, "missing_body");
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      fail(413, "body_too_large");
    }
    chunks.push(value);
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}
async function body(request) {
  if (request.headers.get("Content-Type")?.split(";")[0] !== "application/json")
    fail(415, "json_required");
  try {
    const value = JSON.parse(
      new TextDecoder().decode(await bytes(request, 32768)),
    );
    if (!value || typeof value !== "object" || Array.isArray(value))
      fail(400, "invalid_body");
    return value;
  } catch (error) {
    if (error instanceof APIError) throw error;
    fail(400, "invalid_json");
  }
}
const blocked = (a, b) =>
  `exists(select 1 from blocks where (blocker_id=${a} and blocked_id=${b}) or (blocker_id=${b} and blocked_id=${a}))`;
const connected = (a, b) =>
  `(exists(select 1 from friendships where user_low=min(${a},${b}) and user_high=max(${a},${b})) and not ${blocked(a, b)})`;
const readable = (actor, owner) =>
  `(${owner}=${actor} or ${connected(actor, owner)})`;
const profileReadable = `(p.id=?1 or (not ${blocked("?1", "p.id")} and (${connected("?1", "p.id")} or pref.allow_id_search=1 or exists(select 1 from friend_requests where status='pending' and ((from_id=?1 and to_id=p.id) or (from_id=p.id and to_id=?1))))))`;

async function route(request, env) {
  // D1 bindings are private to this Worker. Never expose arbitrary table/SQL APIs.
  const db = env.DB;
  const stmt = (sql, ...args) => db.prepare(sql).bind(...args);
  const all = async (sql, ...args) => (await stmt(sql, ...args).all()).results;
  const one = (sql, ...args) => stmt(sql, ...args).first();
  const run = (sql, ...args) => stmt(sql, ...args).run();
  const url = new URL(request.url),
    path = url.pathname,
    method = request.method;
  if (path.startsWith("/v1/auth/") && method === "POST") {
    const result = await env.AUTH_RATE_LIMITER.limit({
      key: request.headers.get("CF-Connecting-IP") ?? "local",
    });
    if (!result.success) fail(429, "rate_limited");
  }
  if (path === "/v1/restaurant-photo" && method === "POST") {
    const b = await body(request);
    const query = {
      name: text(b.name, 200, 1).trim(),
      latitude: number(b.latitude, -90, 90),
      longitude: number(b.longitude, -180, 180),
    };
    if (!query.name) fail(400, "invalid_name");
    const limit = await env.PHOTO_RATE_LIMITER.limit({
      key: request.headers.get("CF-Connecting-IP") ?? "local",
    });
    if (!limit.success) fail(429, "rate_limited");
    if (!env.HOTPEPPER_API_KEY?.trim()) fail(503, "photo_unavailable");
    try {
      return json({
        photo: await findRestaurantPhoto(query, env.HOTPEPPER_API_KEY),
      });
    } catch (error) {
      if (error instanceof HotPepperError) fail(502, "photo_unavailable");
      throw error;
    }
  }
  if (path === "/health" && method === "GET") return json({ status: "ok" });
  if (path === "/v1/auth/challenge" && method === "POST") {
    const nonce = randomToken();
    const digest = await hash(nonce);
    await db.batch([
      stmt("delete from auth_challenges where expires_at<=?", now()),
      stmt(
        "insert into auth_challenges(nonce_hash,expires_at) values(?,?)",
        digest,
        now() + 600,
      ),
    ]);
    return json({ nonce, nonce_hash: digest, expires_in: 600 });
  }
  if (path === "/v1/auth/apple" && method === "POST") {
    const b = await body(request);
    const digest = await hash(text(b.nonce, 64, 64));
    if (
      !(await one(
        "select 1 from auth_challenges where nonce_hash=? and expires_at>?",
        digest,
        now(),
      ))
    )
      fail(401, "invalid_auth");
    let subject;
    try {
      subject = await verifyAppleIdentity(
        text(b.identity_token, 16384, 1),
        digest,
        env.APPLE_CLIENT_ID,
      );
    } catch {
      fail(401, "invalid_auth");
    }
    const token = randomToken(),
      tokenHash = await hash(token),
      userID = crypto.randomUUID(),
      expires = now() + 30 * 86400;
    // The consumed challenge is claimed in the same transaction as the session.
    // A concurrent replay aborts the whole batch through the NOT NULL constraint.
    await db.batch([
      stmt(
        "insert into users(id,apple_subject) values(?,?) on conflict(apple_subject) do nothing",
        userID,
        subject,
      ),
      stmt(
        "insert into profiles(id,display_name,handle) select id,'ユーザー','u_'||replace(id,'-','') from users where apple_subject=? on conflict(id) do nothing",
        subject,
      ),
      stmt(
        "insert into profile_preferences(user_id) select id from users where apple_subject=? on conflict do nothing",
        subject,
      ),
      stmt(
        "insert into sessions(token_hash,user_id,expires_at) values(?,(select id from users where apple_subject=? and exists(select 1 from auth_challenges where nonce_hash=? and expires_at>?)),?)",
        tokenHash,
        subject,
        digest,
        now(),
        expires,
      ),
      stmt("delete from auth_challenges where nonce_hash=?", digest),
      stmt("delete from sessions where expires_at<=?", now()),
    ]);
    const user = await one(
      "select id from users where apple_subject=?",
      subject,
    );
    return json({ access_token: token, expires_at: expires, user_id: user.id });
  }
  if (path === "/v1/restaurants" && method === "GET") {
    const bounds = parseBounds(url);
    return json(
      await all(
        "select * from restaurants where latitude between ? and ? and longitude between ? and ? order by id limit 1000",
        bounds[0],
        bounds[2],
        bounds[1],
        bounds[3],
      ),
    );
  }
  const bearer = request.headers.get("Authorization");
  if (!bearer || !/^Bearer [a-f0-9]{64}$/.test(bearer))
    fail(401, "authentication_required");
  const tokenHash = await hash(bearer.slice(7));
  const session = await one(
    "select user_id from sessions where token_hash=? and expires_at>?",
    tokenHash,
    now(),
  );
  if (!session) fail(401, "authentication_required");
  const actor = session.user_id;
  if (path === "/v1/auth/session" && method === "DELETE") {
    await run("delete from sessions where token_hash=?", tokenHash);
    return json({ ok: true });
  }
  if (path === "/v1/me" && method === "GET")
    return json(
      await one(
        "select id,display_name,handle,avatar_path,created_at from profiles where id=?",
        actor,
      ),
    );
  if (path === "/v1/me" && method === "PATCH") {
    const b = await body(request);
    const name = text(b.display_name, 40, 1),
      handle = text(b.handle, 40, 3);
    if (!/^[a-z0-9_.]+$/.test(handle)) fail(400, "invalid_handle");
    await run(
      "update profiles set display_name=?,handle=? where id=?",
      name,
      handle,
      actor,
    );
    return json({ ok: true });
  }
  if (path === "/v1/preferences" && method === "GET")
    return json(
      await one("select * from profile_preferences where user_id=?", actor),
    );
  if (path === "/v1/preferences" && method === "PUT") {
    const b = await body(request);
    await run(
      "update profile_preferences set allow_id_search=?,show_visit_date=?,include_in_friend_avg=? where user_id=?",
      bool(b.allow_id_search),
      bool(b.show_visit_date),
      bool(b.include_in_friend_avg),
      actor,
    );
    return json({ ok: true });
  }
  if (path === "/v1/profiles" && method === "GET") {
    const handle = text(url.searchParams.get("handle"), 40, 3);
    return json(
      await all(
        `select p.* from profiles p join profile_preferences pref on pref.user_id=p.id where ${profileReadable} and p.handle=?2 limit 1`,
        actor,
        handle,
      ),
    );
  }
  const profileMatch = path.match(/^\/v1\/profiles\/([^/]+)$/);
  if (profileMatch && method === "GET") {
    const profile = await one(
      `select p.* from profiles p join profile_preferences pref on pref.user_id=p.id where ${profileReadable} and p.id=?2`,
      actor,
      id(profileMatch[1]),
    );
    if (!profile) fail(404, "not_found");
    return json(profile);
  }
  if (path === "/v1/friends" && method === "GET")
    return json(
      await all(
        `select p.*,exists(select 1 from favorite_friends where user_id=?1 and friend_id=p.id) as is_favorite from profiles p where p.id<>?1 and ${connected("?1", "p.id")} order by p.id limit 1000`,
        actor,
      ),
    );
  if (path === "/v1/requests" && method === "GET")
    return json(
      await all(
        `select * from friend_requests where (from_id=?1 or to_id=?1) and not ${blocked("from_id", "to_id")} order by created_at desc limit 1000`,
        actor,
      ),
    );
  if (path === "/v1/requests" && method === "POST") {
    const b = await body(request),
      target = id(b.target_id);
    if (actor === target) fail(400, "invalid_target");
    const result = await one(
      `insert into friend_requests(id,from_id,to_id) values(?,?,?) on conflict(from_id,to_id) do update set status='pending',created_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') returning id`,
      crypto.randomUUID(),
      actor,
      target,
    );
    return json(result, 201);
  }
  const requestMatch = path.match(/^\/v1\/requests\/([^/]+)$/);
  if (requestMatch && method === "PATCH") {
    const b = await body(request),
      requestID = id(requestMatch[1]);
    const status = bool(b.accept) ? "accepted" : "declined";
    const result = await one(
      "update friend_requests set status=? where id=? and to_id=? and status='pending' returning id",
      status,
      requestID,
      actor,
    );
    if (!result) fail(404, "not_found");
    return json({ ok: true });
  }
  if (requestMatch && method === "DELETE") {
    const result = await one(
      "delete from friend_requests where id=? and from_id=? and status='pending' returning id",
      id(requestMatch[1]),
      actor,
    );
    if (!result) fail(404, "not_found");
    return json({ ok: true });
  }
  const friendMatch = path.match(/^\/v1\/friends\/([^/]+)(\/favorite)?$/);
  if (friendMatch) {
    const target = id(friendMatch[1]);
    if (actor === target) fail(400, "invalid_target");
    if (friendMatch[2] && method === "PUT") {
      await run(
        "insert into favorite_friends(user_id,friend_id) values(?,?) on conflict do nothing",
        actor,
        target,
      );
      return json({ ok: true });
    }
    if (friendMatch[2] && method === "DELETE") {
      await run(
        "delete from favorite_friends where user_id=? and friend_id=?",
        actor,
        target,
      );
      return json({ ok: true });
    }
    if (!friendMatch[2] && method === "DELETE") {
      await db.batch([
        stmt(
          "delete from friendships where user_low=min(?1,?2) and user_high=max(?1,?2)",
          actor,
          target,
        ),
        stmt(
          "delete from friend_requests where (from_id=?1 and to_id=?2) or (from_id=?2 and to_id=?1)",
          actor,
          target,
        ),
      ]);
      return json({ ok: true });
    }
  }
  if (path === "/v1/blocks" && method === "GET")
    return json(
      await all(
        "select blocked_id from blocks where blocker_id=? order by blocked_id limit 1000",
        actor,
      ),
    );
  const blockMatch = path.match(/^\/v1\/blocks\/([^/]+)$/);
  if (blockMatch && ["PUT", "DELETE"].includes(method)) {
    const target = id(blockMatch[1]);
    if (target === actor) fail(400, "invalid_target");
    if (method === "PUT")
      await run(
        "insert into blocks(blocker_id,blocked_id) values(?,?) on conflict do nothing",
        actor,
        target,
      );
    else
      await run(
        "delete from blocks where blocker_id=? and blocked_id=?",
        actor,
        target,
      );
    return json({ ok: true });
  }
  if (path === "/v1/restaurants" && method === "POST") {
    const b = await body(request);
    const result = await one(
      "insert into restaurants(id,external_key,name,category,address,latitude,longitude) values(?,?,?,?,?,?,?) on conflict(external_key) do update set external_key=excluded.external_key returning *",
      crypto.randomUUID(),
      text(b.external_key, 300, 1),
      text(b.name, 200, 1),
      b.category == null ? null : text(b.category, 100),
      text(b.address ?? "", 500),
      number(b.latitude, -90, 90),
      number(b.longitude, -180, 180),
    );
    return json(result, 201);
  }
  if (path === "/v1/ratings" && method === "GET") {
    const [minLat, minLng, maxLat, maxLng] = parseBounds(url);
    const raw = url.searchParams.get("friend_ids");
    const ids = raw === null ? null : raw === "" ? [] : raw.split(",").map(id);
    if (ids && ids.length > 100) fail(400, "too_many_friends");
    const filter =
      ids === null ? "" : `and r.user_id in (select value from json_each(?6))`;
    return json(
      await all(
        `select r.restaurant_id,avg(r.rating) as average_rating,count(*) as friend_count from reviews r join restaurants p on p.id=r.restaurant_id join profile_preferences pref on pref.user_id=r.user_id where ${connected("?1", "r.user_id")} and pref.include_in_friend_avg=1 and p.latitude between ?2 and ?3 and p.longitude between ?4 and ?5 ${filter} group by r.restaurant_id order by r.restaurant_id limit 1000`,
        ...[
          actor,
          minLat,
          maxLat,
          minLng,
          maxLng,
          ...(ids === null ? [] : [JSON.stringify(ids)]),
        ],
      ),
    );
  }
  if (path === "/v1/reviews" && method === "GET") {
    const restaurant = id(url.searchParams.get("restaurant_id"));
    return json(
      await all(
        `select r.*,case when r.user_id=?1 or pref.show_visit_date=1 then v.visited_on else null end as visited_on from reviews r join profile_preferences pref on pref.user_id=r.user_id left join review_visits v on v.review_id=r.id where r.restaurant_id=?2 and ${readable("?1", "r.user_id")} order by r.updated_at desc,r.id limit 1000`,
        actor,
        restaurant,
      ),
    );
  }
  if (path === "/v1/me/reviews" && method === "GET")
    return json(
      await all(
        "select r.*,v.visited_on from reviews r left join review_visits v on v.review_id=r.id where r.user_id=? order by r.updated_at desc,r.id limit 1000",
        actor,
      ),
    );
  if (path === "/v1/reviews" && method === "PUT") {
    const b = await body(request),
      restaurant = id(b.restaurant_id),
      rating = number(b.rating, 1, 5);
    if (!Number.isInteger(rating * 2)) fail(400, "invalid_rating");
    const comment = text(b.comment ?? "", 300),
      dish = text(b.dish ?? "", 100),
      again = bool(b.want_again ?? false);
    const visit = b.visited_on ?? null;
    if (
      visit !== null &&
      (typeof visit !== "string" ||
        !/^\d{4}-\d{2}-\d{2}$/.test(visit) ||
        !Number.isFinite(Date.parse(visit)) ||
        new Date(visit).toISOString().slice(0, 10) !== visit)
    )
      fail(400, "invalid_date");
    const reviewID = crypto.randomUUID();
    const ops = [
      stmt(
        "insert into reviews(id,user_id,restaurant_id,rating,comment,dish,want_again) values(?,?,?,?,?,?,?) on conflict(user_id,restaurant_id) do update set rating=excluded.rating,comment=excluded.comment,dish=excluded.dish,want_again=excluded.want_again returning id",
        reviewID,
        actor,
        restaurant,
        rating,
        comment,
        dish,
        again,
      ),
    ];
    if (visit === null)
      ops.push(
        stmt(
          "delete from review_visits where review_id in (select id from reviews where user_id=? and restaurant_id=?)",
          actor,
          restaurant,
        ),
      );
    else
      ops.push(
        stmt(
          "insert into review_visits(review_id,user_id,visited_on) select id,user_id,? from reviews where user_id=? and restaurant_id=? on conflict(review_id) do update set visited_on=excluded.visited_on",
          visit,
          actor,
          restaurant,
        ),
      );
    const result = await db.batch(ops);
    return json(result[0].results[0]);
  }
  const reviewMatch = path.match(/^\/v1\/reviews\/([^/]+)$/);
  if (reviewMatch && method === "DELETE") {
    // R2 objects remain private; the owner can delete them even after metadata cascades.
    const result = await one(
      "delete from reviews where id=? and user_id=? returning id",
      id(reviewMatch[1]),
      actor,
    );
    if (!result) fail(404, "not_found");
    return json({ ok: true });
  }
  if (path === "/v1/saved" && method === "GET")
    return json(
      await all(
        "select * from saved_restaurants where user_id=? order by saved_at desc,restaurant_id limit 1000",
        actor,
      ),
    );
  const savedMatch = path.match(/^\/v1\/saved\/([^/]+)$/);
  if (savedMatch && method === "PUT") {
    const restaurant = id(savedMatch[1]),
      b = await body(request),
      status = b.status ?? null;
    if (![null, "want_to_go", "visited"].includes(status))
      fail(400, "invalid_status");
    const favorite = bool(b.is_favorite);
    if (status === null && !favorite) fail(400, "empty_save");
    await run(
      "insert into saved_restaurants(user_id,restaurant_id,status,is_favorite) values(?,?,?,?) on conflict(user_id,restaurant_id) do update set status=excluded.status,is_favorite=excluded.is_favorite",
      actor,
      restaurant,
      status,
      favorite,
    );
    return json({ ok: true });
  }
  if (savedMatch && method === "DELETE") {
    await run(
      "delete from saved_restaurants where user_id=? and restaurant_id=?",
      actor,
      id(savedMatch[1]),
    );
    return json({ ok: true });
  }
  if (path === "/v1/photos" && method === "GET") {
    const review = id(url.searchParams.get("review_id"));
    return json(
      await all(
        `select p.* from review_photos p where p.review_id=?2 and ${readable("?1", "p.user_id")} order by slot`,
        actor,
        review,
      ),
    );
  }
  if (path === "/v1/photos" && method === "POST") {
    const b = await body(request),
      review = id(b.review_id),
      slot = number(b.slot, 1, 5);
    if (!Number.isInteger(slot)) fail(400, "invalid_slot");
    const result = await one(
      "insert into review_photos(id,review_id,user_id,slot) select ?,id,user_id,? from reviews where id=? and user_id=? returning *",
      crypto.randomUUID(),
      slot,
      review,
      actor,
    );
    if (!result) fail(404, "not_found");
    return json(result, 201);
  }
  const photoMatch = path.match(/^\/v1\/photos\/([^/]+)$/);
  if (photoMatch && method === "DELETE") {
    const photo = await one(
      "delete from review_photos where id=? and user_id=? returning object_path",
      id(photoMatch[1]),
      actor,
    );
    if (!photo) fail(404, "not_found");
    await env.PHOTOS.delete(photo.object_path);
    return json({ ok: true });
  }
  const objectMatch = path.match(
    /^\/v1\/objects\/([^/]+)\/([^/]+)\/([^/]+)\.jpg$/,
  );
  if (objectMatch) {
    const [owner, review, photo] = objectMatch.slice(1).map(id),
      key = `${owner}/${review}/${photo}.jpg`;
    if (method === "DELETE") {
      if (owner !== actor) fail(404, "not_found");
      await env.PHOTOS.delete(key);
      return json({ ok: true });
    }
    if (method === "PUT") {
      if (
        owner !== actor ||
        !(await one(
          "select 1 from review_photos where object_path=? and user_id=?",
          key,
          actor,
        ))
      )
        fail(404, "not_found");
      if (request.headers.get("Content-Type") !== "image/jpeg")
        fail(415, "jpeg_required");
      const data = await bytes(request, MAX_PHOTO);
      if (
        data.length < 4 ||
        data[0] !== 255 ||
        data[1] !== 216 ||
        data[data.length - 2] !== 255 ||
        data[data.length - 1] !== 217
      )
        fail(400, "invalid_jpeg");
      await env.PHOTOS.put(key, data, {
        httpMetadata: { contentType: "image/jpeg" },
      });
      return json({ ok: true });
    }
    if (method === "GET") {
      // Always authorize from current D1 state; no public/signed URLs or edge cache.
      const allowed = await one(
        `select 1 from review_photos p where p.object_path=?2 and ${readable("?1", "p.user_id")}`,
        actor,
        key,
      );
      if (!allowed) fail(404, "not_found");
      const object = await env.PHOTOS.get(key);
      if (!object) fail(404, "not_found");
      return new Response(object.body, {
        headers: {
          "Content-Type": "image/jpeg",
          "Cache-Control": "private, no-store",
          "X-Content-Type-Options": "nosniff",
        },
      });
    }
  }
  fail(404, "not_found");
}
function parseBounds(url) {
  const keys = ["min_lat", "min_lng", "max_lat", "max_lng"];
  const values = keys.map((key, i) => {
    const raw = url.searchParams.get(key);
    if (raw === null || raw.trim() === "") fail(400, "bounds_required");
    return number(Number(raw), i % 2 ? -180 : -90, i % 2 ? 180 : 90);
  });
  if (values[0] > values[2] || values[1] > values[3])
    fail(400, "invalid_bounds");
  return values;
}
export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof APIError)
        return json({ error: error.message }, error.status);
      // Never return or log SQL, bindings, credentials, user input, or personal data.
      if (
        /constraint|request_not_allowed|friend_required/i.test(
          String(error?.message),
        )
      )
        return json({ error: "conflict" }, 409);
      return json({ error: "internal_error" }, 500);
    }
  },
};
