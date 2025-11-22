import cf from 'cloudfront';

// 関連付け済みの KeyValueStore を取得
const kvsHandle = cf.kvs();

async function handler(event) {
  const request = event.request;
  const headers = request.headers || {};

  const authHeader = headers.authorization && headers.authorization.value;

  let expected = null;
  try {
    // Terraform 側で登録した key = "basic_auth_header"
    // value = "Basic <base64(username:password)>"
    expected = await kvsHandle.get("basic_auth_header", { format: "string" });
  } catch (err) {
    // KVS 取得に失敗したらログだけ出して認証エラー扱い
    console.log("kvs get failed: " + err);
  }

  // 認証 OK: Authorization をオリジンに渡さないよう削除してそのまま進める
  if (expected && authHeader === expected) {
    delete headers.authorization;
    request.headers = headers;
    return request;
  }

  // 認証 NG: 401 を返す
  return {
    statusCode: 401,
    statusDescription: "Unauthorized",
    headers: {
      "www-authenticate": { value: 'Basic realm="Restricted"' },
      "cache-control":    { value: "no-store" },
      "content-type":     { value: "text/html; charset=utf-8" }
    },
    body: "<html><body><h1>401 Unauthorized</h1><p>Authentication required.</p></body></html>"
  };
}
