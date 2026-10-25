import { test, mock } from "node:test";
import assert from "node:assert/strict";
import {
  findRestaurantPhoto,
  selectPhoto,
  IMAGE_CREDIT,
} from "../src/hotpepper.js";
import worker from "../src/index.js";
const query = { name: "テスト食堂 丸の内店", latitude: 35, longitude: 139 };
const fixture = {
  id: "J000000001",
  name: "テスト食堂　丸の内店",
  lat: "35.0001",
  lng: "139.0001",
  photo: {
    pc: {
      l: "https://imgfp.hotp.jp/IMGH/fixture/l.jpg",
      s: "https://imgfp.hotp.jp/IMGH/fixture/s.jpg",
    },
  },
  urls: { pc: "https://www.hotpepper.jp/strJ000000001/" },
};
const env = {
  HOTPEPPER_API_KEY: "synthetic-hotpepper-fixture",
  PHOTO_RATE_LIMITER: { limit: async () => ({ success: true }) },
};
async function api(value, bindings = env) {
  return worker.fetch(
    new Request("https://api.example.test/v1/restaurant-photo", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(value),
    }),
    bindings,
  );
}

test("unique nearby normalized name uses top photo, thumbnail and attribution", () => {
  const photo = selectPhoto([fixture], query);
  assert.equal(photo.shop_id, fixture.id);
  assert.equal(photo.image_url, fixture.photo.pc.l);
  assert.equal(photo.thumbnail_url, fixture.photo.pc.s);
  assert.equal(photo.image_credit, IMAGE_CREDIT);
  assert.equal(photo.service_url, "https://webservice.recruit.co.jp/");
});
test("another branch, remote coordinates, malformed coordinates and duplicate matches do not guess a photo", () => {
  for (const shops of [
    [],
    [{ ...fixture, name: "テスト食堂 新宿店" }],
    [{ ...fixture, lat: 36 }],
    [{ ...fixture, lat: null }],
    [{ ...fixture, lng: "NaN" }],
    [{ ...fixture, lat: 100 }],
    [fixture, { ...fixture, id: "J000000002" }],
  ]) {
    assert.equal(selectPhoto(shops, query), null);
  }
  assert.equal(selectPhoto([fixture], { ...query, name: "テスト食堂" }), null);
});
test("reject arbitrary and credential-bearing links; upgrade provider HTTP links to HTTPS", () => {
  for (const url of [
    "https://attacker.example.test/a.jpg",
    "https://imgfp.hotp.jp.attacker.example.test/a.jpg",
    "https://fixture:secret@imgfp.hotp.jp/a.jpg",
    "http://127.0.0.1/a.jpg",
    "javascript:alert(1)",
  ]) {
    assert.equal(
      selectPhoto([{ ...fixture, photo: { pc: { l: url } } }], query),
      null,
    );
  }
  assert.equal(
    selectPhoto(
      [{ ...fixture, urls: { pc: "https://attacker.example.test/" } }],
      query,
    ),
    null,
  );
  const photo = selectPhoto(
    [{ ...fixture, photo: { pc: { l: "http://imgfp.hotp.jp/a.jpg" } } }],
    query,
  );
  assert.equal(photo.image_url, "https://imgfp.hotp.jp/a.jpg");
  assert.equal(photo.thumbnail_url, photo.image_url);
});
test("API request uses fixed HTTPS endpoint and server-only key, location and name filters", async () => {
  const photo = await findRestaurantPhoto(
    query,
    env.HOTPEPPER_API_KEY,
    async (url, options) => {
      assert.equal(url.origin, "https://webservice.recruit.co.jp");
      assert.equal(url.pathname, "/hotpepper/gourmet/v1/");
      assert.equal(url.searchParams.get("key"), env.HOTPEPPER_API_KEY);
      assert.equal(url.searchParams.get("name"), query.name);
      assert.equal(url.searchParams.get("lat"), "35");
      assert.equal(url.searchParams.get("range"), "1");
      assert.equal(url.searchParams.get("count"), "100");
      assert.equal(url.searchParams.get("datum"), "world");
      assert.equal(url.searchParams.get("format"), "json");
      assert.equal(options.redirect, "error");
      assert.ok(options.signal);
      return Response.json({
        results: { shop: [fixture], results_available: 1 },
      });
    },
  );
  assert.equal(photo.shop_id, fixture.id);
  assert.ok(!JSON.stringify(photo).includes(env.HOTPEPPER_API_KEY));
});
test("API errors, HTTP errors, malformed results and fetch URL errors are sanitized", async () => {
  const responses = [
    () => new Response("bad", { status: 500 }),
    () =>
      Response.json({ results: { error: [{ message: "synthetic error" }] } }),
    () => Response.json({ results: { shop: [] } }),
    () => new Response("invalid JSON"),
  ];
  for (const response of responses)
    await assert.rejects(
      findRestaurantPhoto(query, env.HOTPEPPER_API_KEY, async () => response()),
      { message: "upstream_unavailable" },
    );
  await assert.rejects(
    findRestaurantPhoto(query, env.HOTPEPPER_API_KEY, async () => {
      throw new Error("secret=" + env.HOTPEPPER_API_KEY);
    }),
    { message: "upstream_unavailable" },
  );
});
test("unlisted and truncated candidate results return no photo", async () => {
  assert.equal(
    await findRestaurantPhoto(query, "fixture", async () =>
      Response.json({ results: { shop: [], results_available: 0 } }),
    ),
    null,
  );
  assert.equal(
    await findRestaurantPhoto(query, "fixture", async () =>
      Response.json({ results: { shop: [fixture], results_available: 101 } }),
    ),
    null,
  );
});
test("public lookup works before sign-in and never exposes provider key", async () => {
  const m = mock.method(globalThis, "fetch", async () =>
    Response.json({ results: { shop: [fixture], results_available: 1 } }),
  );
  try {
    const response = await api(query);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("Cache-Control"), "private, no-store");
    const payload = await response.text();
    assert.ok(!payload.includes(env.HOTPEPPER_API_KEY));
    assert.equal(JSON.parse(payload).photo.shop_id, fixture.id);
  } finally {
    m.mock.restore();
  }
});
test("missing key, bad input, throttling and provider outage fail without leaking data", async () => {
  const m = mock.method(globalThis, "fetch", async () => {
    throw new Error(env.HOTPEPPER_API_KEY);
  });
  try {
    for (const b of [
      { ...query, name: "" },
      { ...query, name: "  " },
      { ...query, name: "あ".repeat(201) },
      { ...query, latitude: 91 },
      { ...query, longitude: "139" },
      { ...query, latitude: null },
    ])
      assert.equal((await api(b)).status, 400);
    assert.equal(
      (await api(query, { ...env, HOTPEPPER_API_KEY: "" })).status,
      503,
    );
    assert.equal(
      (
        await api(query, {
          ...env,
          PHOTO_RATE_LIMITER: { limit: async () => ({ success: false }) },
        })
      ).status,
      429,
    );
    const response = await api(query);
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: "photo_unavailable" });
  } finally {
    m.mock.restore();
  }
});
