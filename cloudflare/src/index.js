import { hash, now, randomToken } from "./auth.js";

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
async function body(request, limit = 32768) {
  if (request.headers.get("Content-Type")?.split(";")[0] !== "application/json")
    fail(415, "json_required");
  try {
    const value = JSON.parse(
      new TextDecoder().decode(await bytes(request, limit)),
    );
    if (!value || typeof value !== "object" || Array.isArray(value))
      fail(400, "invalid_body");
    return value;
  } catch (error) {
    if (error instanceof APIError) throw error;
    fail(400, "invalid_json");
  }
}
// 7 characters from an alphabet without look-alikes, easy to read aloud at a demo.
const guestHandle = () => {
  const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
  return Array.from(
    crypto.getRandomValues(new Uint8Array(7)),
    (b) => alphabet[b % alphabet.length],
  ).join("");
};
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
  const all = async (sql, ...args) => {
    if (sql.endsWith("limit 1000")) {
      const limit = Number(url.searchParams.get("limit") ?? 1000);
      const offset = Number(url.searchParams.get("offset") ?? 0);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000 || !Number.isSafeInteger(offset) || offset < 0) fail(400, "invalid_page");
      sql = sql.replace(/limit 1000$/, "limit ? offset ?");
      args.push(limit, offset);
    }
    return (await stmt(sql, ...args).all()).results;
  };
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
  if (path === "/health" && method === "GET") return json({ status: "ok" });
  if (path === "/v1/auth/guest" && method === "POST") {
    // Hackathon build: the session token is the only credential, so guests keep
    // the same account while the app keeps it in the Keychain.
    const b = await body(request);
    const name = text(b.display_name ?? "ゲスト", 40).trim() || "ゲスト";
    const userID = crypto.randomUUID(),
      token = randomToken(),
      tokenHash = await hash(token),
      expires = now() + 365 * 86400;
    for (let attempt = 0; ; attempt++) {
      const handle = guestHandle();
      try {
        await db.batch([
          stmt(
            "insert into users(id,auth_subject) values(?,?)",
            userID,
            `guest:${userID}`,
          ),
          stmt(
            "insert into profiles(id,display_name,handle) values(?,?,?)",
            userID,
            name,
            handle,
          ),
          // Guests are found by handle so friends can connect without accounts.
          stmt(
            "insert into profile_preferences(user_id,allow_id_search) values(?,1)",
            userID,
          ),
          stmt(
            "insert into sessions(token_hash,user_id,expires_at) values(?,?,?)",
            tokenHash,
            userID,
            expires,
          ),
          stmt("delete from sessions where expires_at<=?", now()),
        ]);
        return json(
          { access_token: token, expires_at: expires, user_id: userID },
          201,
        );
      } catch (error) {
        if (attempt >= 4 || !/constraint/i.test(String(error?.message)))
          throw error;
      }
    }
  }
  if (path === "/v1/auth/recover" && method === "POST") {
    const b = await body(request);
    const key = text(b.recovery_key, 64, 64);
    if (!/^[a-f0-9]{64}$/.test(key)) fail(400, "invalid_key");
    const account = await one("select user_id from recovery_keys where key_hash=?", await hash(key));
    if (!account) fail(401, "authentication_required");
    const token = randomToken(), expires = now() + 365 * 86400;
    await run("insert into sessions(token_hash,user_id,expires_at) values(?,?,?)", await hash(token), account.user_id, expires);
    return json({access_token:token, expires_at:expires, user_id:account.user_id});
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
        "select id,display_name,handle,avatar_path,bio,avatar_symbol,created_at from profiles where id=?",
        actor,
      ),
    );
  if (path === "/v1/me" && method === "PATCH") {
    const b = await body(request);
    const name = text(b.display_name, 40, 1).trim(),
      handle = text(b.handle, 40, 3);
    if (!name || !/^[a-z0-9_.]+$/.test(handle)) fail(400, "invalid_handle");
    await run(
      "update profiles set display_name=?,handle=?,bio=coalesce(?,bio),avatar_symbol=coalesce(?,avatar_symbol) where id=?",
      name,
      handle,
      b.bio === undefined ? null : text(b.bio, 160),
      b.avatar_symbol === undefined ? null : avatar(b.avatar_symbol),
      actor,
    );
    return json({ ok: true });
  }
  if (path === "/v1/me" && method === "DELETE") {
    // Revocation is immediate; inaccessible objects are removed by the scheduled sweep.
    await run("delete from users where id=?", actor);
    return json({ok:true});
  }
  if (path === "/v1/me/recovery-key" && method === "POST") {
    const key = randomToken();
    await run("insert into recovery_keys(user_id,key_hash) values(?,?) on conflict(user_id) do update set key_hash=excluded.key_hash", actor, await hash(key));
    return json({recovery_key:key});
  }
  if (path === "/v1/library" && method === "GET") {
    const row = await one("select version,payload,updated_at from library_backups where user_id=?", actor);
    return json(row ? {version:row.version, snapshot:JSON.parse(row.payload), updated_at:row.updated_at} : {version:0, snapshot:null});
  }
  if (path === "/v1/library" && method === "PUT") {
    const b = await body(request, 1_600_000);
    if (!Number.isSafeInteger(b.version) || b.version < 0 || !b.snapshot || typeof b.snapshot !== "object" || Array.isArray(b.snapshot)) fail(400,"invalid_snapshot");
    const snapshot = b.snapshot;
    if (new TextEncoder().encode(JSON.stringify(snapshot)).length > 1_500_000) fail(413,"backup_too_large");
    if (snapshot.schema !== 1 || !Array.isArray(snapshot.saved) || !Array.isArray(snapshot.reviews) || snapshot.saved.length > 10000 || snapshot.reviews.length > 10000) fail(400,"invalid_snapshot");
    if (b.version !== 0 && !(await one("select 1 from library_backups where user_id=?",actor))) fail(409,"backup_conflict");
    const result = await one("insert into library_backups(user_id,version,payload) values(?,1,?) on conflict(user_id) do update set version=version+1,payload=excluded.payload,updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') where version=? returning version", actor, JSON.stringify(snapshot), b.version);
    if (!result) fail(409,"backup_conflict");
    return json(result);
  }
  const backupPhoto = path.match(/^\/v1\/library\/photos\/([a-fA-F0-9-]{36}\.jpg)$/);
  if (backupPhoto) {
    if (!uuid(backupPhoto[1].slice(0,-4).toLowerCase())) fail(400,"invalid_photo");
    const key = `backup/${actor}/${backupPhoto[1]}`;
    if (method === "PUT") {
      if (request.headers.get("Content-Type") !== "image/jpeg") fail(415,"jpeg_required");
      const data = await bytes(request,MAX_PHOTO);
      if (data.length < 4 || data[0]!==255 || data[1]!==216 || data.at(-2)!==255 || data.at(-1)!==217) fail(400,"invalid_jpeg");
      await env.PHOTOS.put(key,data,{httpMetadata:{contentType:"image/jpeg"}});
      return json({ok:true});
    }
    if (method === "GET") {
      const object = await env.PHOTOS.get(key);
      if (!object) fail(404,"not_found");
      return new Response(object.body,{headers:{"Content-Type":"image/jpeg","Cache-Control":"private, no-store"}});
    }
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
        `select q.*,f.display_name as from_name,f.handle as from_handle,t.display_name as to_name,t.handle as to_handle from friend_requests q join profiles f on f.id=q.from_id join profiles t on t.id=q.to_id where (q.from_id=?1 or q.to_id=?1) and not ${blocked("q.from_id", "q.to_id")} order by q.created_at desc limit 1000`,
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
        "select b.blocked_id,p.display_name from blocks b join profiles p on p.id=b.blocked_id where b.blocker_id=? order by b.blocked_id limit 1000",
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
    const placeID = b.google_place_id == null ? null : text(b.google_place_id, 300, 1);
    if (placeID) {
      const existing = await one("select * from restaurants where google_place_id=? order by id limit 1",placeID);
      if (existing) return json(existing,201);
    }
    const result = await one(
      "insert into restaurants(id,external_key,name,category,address,latitude,longitude,google_place_id) values(?,?,?,?,?,?,?,?) on conflict(external_key) do update set google_place_id=coalesce(restaurants.google_place_id,excluded.google_place_id) on conflict(google_place_id) do update set google_place_id=excluded.google_place_id returning *",
      crypto.randomUUID(),
      text(b.external_key, 300, 1),
      text(b.name, 200, 1),
      b.category == null ? null : text(b.category, 100),
      text(b.address ?? "", 500),
      number(b.latitude, -90, 90),
      number(b.longitude, -180, 180),
      placeID,
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
  // One list powers the friends' map, feed and per-restaurant voices on the client.
  if (path === "/v1/friend-reviews" && method === "GET")
    return json(
      await all(
        `select r.id,r.user_id,p.display_name,r.rating,r.comment,r.dish,r.want_again,r.updated_at,s.id as restaurant_id,s.external_key,s.google_place_id,s.name,s.category,s.address,s.latitude,s.longitude from reviews r join profiles p on p.id=r.user_id join profile_preferences pref on pref.user_id=r.user_id join restaurants s on s.id=r.restaurant_id where r.user_id<>?1 and pref.include_in_friend_avg=1 and ${connected("?1", "r.user_id")} order by r.updated_at desc,r.id limit 1000`,
        actor,
      ),
    );
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
function avatar(value) {
  const symbols = ["person.fill","fork.knife","cup.and.saucer.fill","leaf.fill","fish.fill","carrot.fill","birthday.cake.fill","sun.max.fill"];
  if (!symbols.includes(value)) fail(400,"invalid_avatar");
  return value;
}

// Sweep a bounded page each run. Keep a cursor so large buckets eventually finish.
export async function sweepOrphans(env) {
  const state = await env.DB.prepare("select payload from maintenance_state where id=1").first();
  const page = await env.PHOTOS.list({limit:100,cursor:state?.payload || undefined});
  for (const object of page.objects) {
    if (Date.now() - new Date(object.uploaded).getTime() < 86400000) continue;
    let exists;
    if (object.key.startsWith("backup/")) {
      const [,owner,name] = object.key.split("/");
      const row = await env.DB.prepare("select payload from library_backups where user_id=?").bind(owner).first();
      exists = row && JSON.parse(row.payload).reviews?.some(r => r.photoFileNames?.includes(name));
    } else {
      exists = await env.DB.prepare("select 1 from review_photos where object_path=?").bind(object.key).first();
    }
    if (!exists) await env.PHOTOS.delete(object.key);
  }
  await env.DB.prepare("insert into maintenance_state(id,payload) values(1,?) on conflict(id) do update set payload=excluded.payload").bind(page.truncated ? page.cursor : "").run();
}
export default {
  async scheduled(_event,env,ctx) { ctx.waitUntil(sweepOrphans(env)); },
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
