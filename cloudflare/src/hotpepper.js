const ENDPOINT = "https://webservice.recruit.co.jp/hotpepper/gourmet/v1/";
export const IMAGE_CREDIT = "画像提供：ホットペッパー グルメ";
export const SERVICE_CREDIT = "Powered by ホットペッパーグルメ Webサービス";
export const SERVICE_URL = "https://webservice.recruit.co.jp/";

export class HotPepperError extends Error {}

// Keep branches and word characters; remove only typography differences.
const normalizedName = (value) =>
  value
    .normalize("NFKC")
    .toLocaleLowerCase("ja-JP")
    .replace(/[\p{P}\p{Z}\s]/gu, "");
function distanceMeters(a, b) {
  const rad = (x) => (x * Math.PI) / 180;
  const lat = rad(b.latitude - a.latitude),
    lng = rad(b.longitude - a.longitude);
  const h =
    Math.sin(lat / 2) ** 2 +
    Math.cos(rad(a.latitude)) *
      Math.cos(rad(b.latitude)) *
      Math.sin(lng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
function safeURL(value, kind) {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    if (
      !["http:", "https:"].includes(url.protocol) ||
      url.username ||
      url.password ||
      url.port
    )
      return null;
    // Only the provider's image CDN and store links are returned to the app.
    if (kind === "image" && url.hostname !== "imgfp.hotp.jp") return null;
    if (
      kind === "shop" &&
      !["www.hotpepper.jp", "hotpepper.jp"].includes(url.hostname)
    )
      return null;
    url.protocol = "https:";
    return url.href;
  } catch {
    return null;
  }
}
export function selectPhoto(shops, query) {
  const name = normalizedName(query.name);
  if (!name) return null;
  // Ambiguous matches, including branches in the same building, are not guessed.
  const candidates = shops.filter(
    (shop) =>
      typeof shop?.name === "string" &&
      normalizedName(shop.name) === name &&
      shop.lat !== null &&
      shop.lng !== null &&
      shop.lat !== "" &&
      shop.lng !== "" &&
      Number.isFinite(Number(shop.lat)) &&
      Math.abs(Number(shop.lat)) <= 90 &&
      Number.isFinite(Number(shop.lng)) &&
      Math.abs(Number(shop.lng)) <= 180 &&
      distanceMeters(query, {
        latitude: Number(shop.lat),
        longitude: Number(shop.lng),
      }) <= 150,
  );
  if (candidates.length !== 1) return null;
  const shop = candidates[0];
  if (typeof shop.id !== "string" || !/^J[0-9A-Za-z]+$/.test(shop.id))
    return null;
  const image = safeURL(shop.photo?.pc?.l, "image");
  const thumbnail =
    safeURL(shop.photo?.pc?.s, "image") ??
    safeURL(shop.photo?.pc?.m, "image") ??
    image;
  const shopURL = safeURL(shop.urls?.pc, "shop");
  if (!image || !shopURL) return null;
  return {
    shop_id: shop.id,
    name: shop.name,
    image_url: image,
    thumbnail_url: thumbnail,
    shop_url: shopURL,
    image_credit: IMAGE_CREDIT,
    service_credit: SERVICE_CREDIT,
    service_url: SERVICE_URL,
  };
}

export async function findRestaurantPhoto(query, apiKey, fetcher = fetch) {
  const url = new URL(ENDPOINT);
  for (const [key, value] of Object.entries({
    key: apiKey,
    name: query.name,
    lat: query.latitude,
    lng: query.longitude,
    range: 1,
    datum: "world",
    count: 100,
    format: "json",
    type: "lite",
  })) {
    url.searchParams.set(key, String(value));
  }
  try {
    const response = await fetcher(url, {
      headers: { Accept: "application/json" },
      redirect: "error",
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new HotPepperError();
    const payload = await response.json();
    const results = payload?.results;
    if (!results || results.error || !Array.isArray(results.shop))
      throw new HotPepperError();
    const available = Number(results.results_available);
    if (
      !Number.isInteger(available) ||
      available < 0 ||
      available > results.shop.length
    ) {
      // A truncated response cannot establish that a match is unique.
      if (available > 100) return null;
      throw new HotPepperError();
    }
    return selectPhoto(results.shop, query);
  } catch {
    // Never propagate a fetch error that may include the API key in its URL.
    throw new HotPepperError("upstream_unavailable");
  }
}
