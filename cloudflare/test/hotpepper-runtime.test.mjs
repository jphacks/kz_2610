import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { Miniflare, createFetchMock } from "miniflare";

const query = { name: "架空の食堂", latitude: 35, longitude: 139 };
const fixture = {
  id: "J000000001",
  name: query.name,
  lat: 35,
  lng: 139,
  photo: { pc: { l: "https://imgfp.hotp.jp/fixture.jpg" } },
  urls: { pc: "https://www.hotpepper.jp/strJ000000001/" },
};

async function runtime(upstream, status = 200, headers = {}) {
  const fetchMock = createFetchMock();
  fetchMock.disableNetConnect();
  fetchMock
    .get("https://webservice.recruit.co.jp")
    .intercept({
      method: "GET",
      path: (path) => {
        const url = new URL(path, "https://webservice.recruit.co.jp");
        return (
          url.pathname === "/hotpepper/gourmet/v1/" &&
          url.searchParams.get("key") === "synthetic-runtime-fixture" &&
          url.searchParams.get("name") === query.name
        );
      },
    })
    .reply(status, JSON.stringify(upstream), {
      headers: { "Content-Type": "application/json", ...headers },
    });
  const mf = new Miniflare({
    modules: true,
    modulesRules: [{ type: "ESModule", include: ["**/*.js"] }],
    scriptPath: fileURLToPath(
      new URL("./fixtures/hotpepper-worker.js", import.meta.url),
    ),
    compatibilityDate: "2026-07-30",
    fetchMock,
  });
  try {
    const response = await mf.dispatchFetch("http://localhost/", {
      method: "POST",
      body: JSON.stringify(query),
    });
    const value = await response.json();
    fetchMock.assertNoPendingInterceptors();
    return { status: response.status, value };
  } finally {
    await mf.dispose();
  }
}

test("provider lookup runs inside the actual Workers runtime", async () => {
  const result = await runtime({
    results: { shop: [fixture], results_available: 1 },
  });
  assert.equal(result.status, 200);
  assert.equal(result.value.photo.shop_id, fixture.id);
});

test("Workers rejects upstream redirects without following them or forwarding the API key", async () => {
  const result = await runtime({}, 302, {
    Location: "https://attacker.example.test/",
  });
  assert.equal(result.status, 502);
  assert.deepEqual(result.value, { error: "photo_unavailable" });
});
