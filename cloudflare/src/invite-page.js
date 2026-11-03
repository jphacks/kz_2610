const escape = (value) => String(value).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

// 表示名以外のプロフィール情報や認証情報はWebへ出さない。
export function invitePage(profile, token, appStoreURL) {
  let store;
  try {
    const url = new URL(appStoreURL);
    if (url.protocol === "https:" && url.hostname === "apps.apple.com") store = url.href;
  } catch {}
  const title = profile ? `${profile.display_name}さんからメシノワへの招待です` : "この招待は使えません";
  const content = profile ? `<p>リンクを開いただけでは友達になりません。相手を確認して申請し、承認されるとつながります。</p>
    <a class="button" href="meshinowa://invite/${token}">アプリで開く</a>
    ${store ? `<a class="button secondary" href="${escape(store)}">App Storeで入手</a><p>インストール後は、このページに戻って「アプリで開く」を押してください。</p>` : "<p>アプリは公開準備中です。インストール済みの方は「アプリで開く」から進めます。</p>"}` : "<p>招待が作り直されたか、利用できなくなっています。送ってくれた人に確認してください。</p>";
  return new Response(`<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>メシノワへの招待</title>
    <style>body{background:#FDF8EE;color:#1C1F1D;font-family:system-ui,sans-serif;margin:0;padding:40px 24px;line-height:1.8}main{max-width:420px;margin:auto}h1{font-size:26px;overflow-wrap:anywhere}.button{display:block;padding:12px;margin:16px 0;text-align:center;border-radius:14px;background:#27755B;color:white;text-decoration:none}.secondary{background:white;color:#27755B;border:1px solid #E3E5E2}small{color:#4F5550}</style>
    <main><small>メシノワ</small><h1>${escape(title)}</h1><p>友達の「おいしかった」が、あなたの地図に。</p>${content}</main></html>`, {
    status: profile ? 200 : 404,
    headers: {"Content-Type":"text/html; charset=utf-8","Cache-Control":"private, no-store", "Referrer-Policy":"no-referrer", "X-Content-Type-Options":"nosniff", "Content-Security-Policy":"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"}
  });
}
