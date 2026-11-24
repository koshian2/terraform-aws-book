"use strict";
let config;
let tokens;
const element = (id) => document.getElementById(id);
const base64url = (bytes) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
const random = () => base64url(crypto.getRandomValues(new Uint8Array(32)));

function payload(token) {
  const part = token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/");
  const bytes = Uint8Array.from(atob(part.padEnd(Math.ceil(part.length / 4) * 4, "=")), (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}
function showTokens() {
  element("claims").textContent = JSON.stringify({
    id_token: payload(tokens.id_token),
    access_token: payload(tokens.access_token),
    refresh_token: "取得済み（JWTではないためデコードしません）",
    expires_in: tokens.expires_in,
  }, null, 2);
  element("refresh").disabled = false;
  element("logout").disabled = false;
  element("status").textContent = "ログイン済み。取得したトークンの中身を確認できます。";
}
async function tokenRequest(params) {
  const response = await fetch(`${config.domain}/oauth2/token`, {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({client_id: config.clientId, ...params}),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_description || data.error || `HTTP ${response.status}`);
  return data;
}
async function login() {
  const verifier = random();
  const state = random();
  const nonce = random();
  const challenge = base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
  sessionStorage.setItem("cognito-login", JSON.stringify({verifier, state, nonce, created: Date.now()}));
  const params = new URLSearchParams({
    response_type: "code", client_id: config.clientId, redirect_uri: config.redirectUri,
    scope: config.scope, state, nonce, code_challenge: challenge, code_challenge_method: "S256",
  });
  location.assign(`${config.domain}/oauth2/authorize?${params}`);
}
async function refresh() {
  const updated = await tokenRequest({grant_type: "refresh_token", refresh_token: tokens.refresh_token});
  tokens = {...tokens, ...updated};
  showTokens();
  element("status").textContent = "リフレッシュトークンから新しいトークンを取得しました。";
}
function logout() {
  tokens = undefined;
  sessionStorage.removeItem("cognito-login");
  const params = new URLSearchParams({client_id: config.clientId, logout_uri: config.redirectUri});
  location.assign(`${config.domain}/logout?${params}`);
}
async function start() {
  const response = await fetch("config.json", {cache: "no-store"});
  if (!response.ok) throw new Error("config.jsonを取得できませんでした。");
  config = await response.json();
  const params = new URLSearchParams(location.search);
  if (params.has("code") || params.has("error")) {
    history.replaceState(null, "", location.pathname);
    const saved = sessionStorage.getItem("cognito-login");
    sessionStorage.removeItem("cognito-login");
    const pending = saved ? JSON.parse(saved) : null;
    if (!pending || params.get("state") !== pending.state || Date.now() - pending.created > 600000) {
      throw new Error("ログイン要求のstateが一致しないか期限切れです。再度ログインしてください。");
    }
    if (params.has("error")) throw new Error(params.get("error_description") || params.get("error"));
    const issued = await tokenRequest({
      grant_type: "authorization_code", code: params.get("code"),
      redirect_uri: config.redirectUri, code_verifier: pending.verifier,
    });
    if (payload(issued.id_token).nonce !== pending.nonce) throw new Error("nonceが一致しません。");
    tokens = issued;
    showTokens();
  } else {
    element("status").textContent = "未ログイン。ログインするとトークンの中身を表示します。";
  }
}
for (const [id, action] of Object.entries({login, refresh, logout})) {
  element(id).addEventListener("click", () => Promise.resolve().then(action).catch((error) => {
    element("status").textContent = error.message;
  }));
}
start().catch((error) => { element("status").textContent = error.message; }).finally(() => {
  if (config) {
    element("login").disabled = false;
  }
});
