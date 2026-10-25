#!/usr/bin/env node
// ローカル開発用のダミーデータ（すべて架空）を、ローカルの D1（.wrangler/）に入れる。本番には使わない。
//
//   npm run db:local --prefix cloudflare                     # 先にマイグレーションを適用
//   npm run seed:local --prefix cloudflare                   # ダミーの友達・お店・レビューを入れる
//   npm run seed:local --prefix cloudflare -- --friend <ID>  # アプリのゲスト（友達タブに出るID）と友達にする
//   npm run seed:local --prefix cloudflare -- --near 36.5781,136.6478   # お店を指定した地点の周りに置く（既定は東京駅）
//
// 何度実行しても同じ状態になる（同じIDの行は上書きしない）。
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const friendIndex = args.indexOf("--friend");
const handle = friendIndex >= 0 ? args[friendIndex + 1]?.trim().toLowerCase().replace(/^@/, "") : null;
if (friendIndex >= 0 && !/^[a-z0-9_.]{3,40}$/.test(handle ?? "")) {
  console.error("--friend にはアプリの友達タブに出るID（英小文字・数字3文字以上）を指定してください。");
  process.exit(1);
}

const nearIndex = args.indexOf("--near");
let center = { lat: 35.6812, lng: 139.7671 }; // 東京駅（アプリの既定エリア）
if (nearIndex >= 0) {
  const [lat, lng] = (args[nearIndex + 1] ?? "").split(",").map(Number);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    console.error("--near には「緯度,経度」を指定してください（例：36.5781,136.6478）。");
    process.exit(1);
  }
  center = { lat, lng };
}

// 中心からのずれで置く。最後の1軒だけ半径1kmの外（「範囲を広げる」の確認用）。
// 同じお店IDのまま場所だけ変わらないよう、--near を変えた時はローカルDBを作り直してください。
const friends = [
  ["d0000000-0000-4000-8000-000000000001", "dummy_aoi", "あおい"],
  ["d0000000-0000-4000-8000-000000000002", "dummy_ren", "れん"],
  ["d0000000-0000-4000-8000-000000000003", "dummy_hina", "ひな"],
  ["d0000000-0000-4000-8000-000000000004", "dummy_sota", "そうた"],
  ["d0000000-0000-4000-8000-000000000005", "dummy_mei", "めい"],
];
const shopOffsets = [
  ["e0000000-0000-4000-8000-000000000001", "【テスト】麺処しおさい", "MKPOICategoryRestaurant", 0.0023, -0.0016],
  ["e0000000-0000-4000-8000-000000000002", "【テスト】喫茶こはる", "MKPOICategoryCafe", -0.0012, 0.0029],
  ["e0000000-0000-4000-8000-000000000003", "【テスト】ぱん工房むぎ", "MKPOICategoryBakery", 0.0033, 0.0054],
  ["e0000000-0000-4000-8000-000000000004", "【テスト】炭火やきとり灯", "MKPOICategoryBrewery", -0.0042, -0.0031],
  ["e0000000-0000-4000-8000-000000000005", "【テスト】洋食キッチンまど", "MKPOICategoryRestaurant", -0.0022, 0.0044],
  ["e0000000-0000-4000-8000-000000000006", "【テスト】すし処なぎさ", "MKPOICategoryRestaurant", 0.0048, -0.0031],
  ["e0000000-0000-4000-8000-000000000007", "【テスト】点心楼", "MKPOICategoryRestaurant", -0.0072, 0.0019],
  ["e0000000-0000-4000-8000-000000000008", "【テスト】遠くの定食屋", "MKPOICategoryRestaurant", 0.0138, 0.0039],
];
const round = (value) => Math.round(value * 1e6) / 1e6;
const shops = shopOffsets.map(([id, name, category, dLat, dLng]) =>
  [id, name, category, "（架空の住所）", round(center.lat + dLat), round(center.lng + dLng)]);
// [レビューID末尾, 友達番号, お店番号, 評価, ひとこと, おすすめ料理, 何日前]
const reviews = [
  [1, 1, 1, 4.5, "あっさり塩で毎日でも行ける。", "塩らーめん", 1],
  [2, 2, 1, 4, "細麺が好み。昼は並ぶ。", "", 3],
  [3, 3, 2, 5, "プリンとコーヒーの組み合わせが最高。", "固めプリン", 2],
  [4, 5, 2, 4.5, "読書したい日にぴったり。", "", 6],
  [5, 4, 3, 4, "焼きたてのクロワッサンを狙うなら朝。", "クロワッサン", 4],
  [6, 1, 4, 4.5, "つくねが絶品。仕事帰りに。", "つくね", 5],
  [7, 2, 4, 3.5, "少し騒がしいけど味はいい。", "", 9],
  [8, 3, 5, 5, "デミグラスのオムライスが好き。", "オムライス", 1],
  [9, 4, 6, 4, "ランチのちらしがお得。", "ちらし寿司", 7],
  [10, 5, 7, 3.5, "小籠包の肉汁がすごい。", "小籠包", 10],
  [11, 1, 8, 4, "ボリューム満点の定食。", "生姜焼き定食", 2],
];

// アプリの店舗IDと同じ「店名|緯度×1万|経度×1万」（SavedRestaurant.identifier）。
const externalKey = (name, lat, lng) => `${name.trim()}|${Math.round(lat * 10000)}|${Math.round(lng * 10000)}`;
const q = (value) => (value === null ? "null" : `'${String(value).replaceAll("'", "''")}'`);
const daysAgo = (days) => new Date(Date.now() - days * 86400000).toISOString();

const sql = [];
for (const [id, h, name] of friends) {
  sql.push(`insert or ignore into users(id,auth_subject) values(${q(id)},${q(`dummy:${id}`)});`);
  sql.push(`insert or ignore into profiles(id,display_name,handle) values(${q(id)},${q(name)},${q(h)});`);
  sql.push(`insert or ignore into profile_preferences(user_id,allow_id_search) values(${q(id)},1);`);
}
for (const [id, name, category, address, lat, lng] of shops) {
  sql.push(
    `insert or ignore into restaurants(id,external_key,name,category,address,latitude,longitude) values(${[id, externalKey(name, lat, lng), name, category, address].map(q).join(",")},${lat},${lng});`,
  );
}
for (const [n, friend, shop, rating, comment, dish, days] of reviews) {
  const id = `f0000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  const at = daysAgo(days);
  sql.push(
    `insert or ignore into reviews(id,user_id,restaurant_id,rating,comment,dish,created_at,updated_at) values(${[id, friends[friend - 1][0], shops[shop - 1][0]].map(q).join(",")},${rating},${q(comment)},${q(dish)},${q(at)},${q(at)});`,
  );
}
if (handle) {
  const ids = friends.map(([id]) => q(id)).join(",");
  sql.push(
    `insert or ignore into friendships(user_low,user_high) select min(g.id,d.id),max(g.id,d.id) from profiles g, profiles d where g.handle=${q(handle)} and d.id in (${ids});`,
  );
  // 2人を「お気に入りの友達」に（Friend Lens の確認用）。
  for (const [id] of friends.slice(0, 2)) {
    sql.push(
      `insert or ignore into favorite_friends(user_id,friend_id) select g.id,${q(id)} from profiles g where g.handle=${q(handle)};`,
    );
  }
}

const dir = mkdtempSync(join(tmpdir(), "meshinowa-seed-"));
const file = join(dir, "seed.sql");
writeFileSync(file, sql.join("\n") + "\n");
try {
  execFileSync("npx", ["wrangler", "d1", "execute", "DB", "--local", "--config", "wrangler.local.jsonc", "--file", file], {
    cwd: root,
    stdio: "inherit",
  });
  if (handle) {
    const found = execFileSync(
      "npx",
      ["wrangler", "d1", "execute", "DB", "--local", "--config", "wrangler.local.jsonc", "--json", "--command",
        `select count(*) as n from profiles where handle=${q(handle)}`],
      { cwd: root, encoding: "utf8" },
    );
    if (!found.includes('"n": 1') && !found.includes('"n":1')) {
      console.warn(`ID「${handle}」のゲストが見つかりませんでした。アプリを一度起動してゲストを作ってから、もう一度実行してください。`);
    } else {
      console.log(`ID「${handle}」をダミーの友達${friends.length}人とつなぎました。`);
    }
  }
  console.log(`ダミーの友達${friends.length}人・お店${shops.length}軒・レビュー${reviews.length}件を入れました（ローカルのみ）。`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
