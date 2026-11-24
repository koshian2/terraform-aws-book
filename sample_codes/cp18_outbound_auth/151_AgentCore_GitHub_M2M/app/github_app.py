"""GitHub App authentication. Credentials stay server-side and redirects are rejected."""
import asyncio
from datetime import datetime
import time

import httpx
import jwt

API = "https://api.github.com"
VERSION = "2026-03-10"


class GitHubError(Exception):
    def __init__(self, stage, status):
        self.stage, self.status = stage, status
        super().__init__(f"GitHub {stage}: HTTP {status}")


def app_jwt(client_id, private_key):
    now = int(time.time())
    return jwt.encode({"iss": client_id, "iat": now - 60, "exp": now + 540}, private_key, algorithm="RS256")


def headers(token):
    return {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": VERSION}


def check(response, expected, stage):
    if response.status_code != expected:
        # Never include response bodies, authorization headers, or signed JWTs.
        raise GitHubError(stage, response.status_code)
    return response.json()


async def discover_installation(client_id, private_key, repository):
    async with httpx.AsyncClient(timeout=30, follow_redirects=False) as http:
        response = await http.get(f"{API}/repos/{repository}/installation", headers=headers(app_jwt(client_id, private_key)))
    data = check(response, 200, "installation discovery")
    if data.get("suspended_at"):
        raise ValueError("GitHub App installation is suspended")
    if data.get("permissions", {}).get("issues") not in ("read", "write"):
        raise ValueError("The App installation needs Issues: read permission")
    return data["id"]


class GitHubApp:
    def __init__(self, client_id, installation_id, repository, key_loader, transport=None):
        self.client_id = client_id
        self.installation_id = int(installation_id)
        if self.installation_id <= 0:
            raise ValueError("Installation ID must be positive")
        self.repository = repository
        self.key_loader = key_loader
        self.transport = transport
        self._token = None
        self._expires = 0
        self._lock = asyncio.Lock()

    async def token(self, http):
        async with self._lock:
            if self._token and time.time() < self._expires - 60:
                return self._token
            private_key = await asyncio.to_thread(self.key_loader)
            signed = app_jwt(self.client_id, private_key)
            # Ensure the configured installation belongs to this exact owner/repo.
            response = await http.get(f"{API}/repos/{self.repository}/installation", headers=headers(signed))
            installation = check(response, 200, "installation lookup")
            if installation["id"] != self.installation_id or installation.get("suspended_at"):
                raise ValueError("Installation mismatch or suspended installation")
            response = await http.post(f"{API}/app/installations/{self.installation_id}/access_tokens",
                                       headers=headers(signed), json={
                                           "repositories": [self.repository.split("/", 1)[1]],
                                           "permissions": {"issues": "read"},
                                       })
            data = check(response, 201, "token issuance")
            self._expires = datetime.fromisoformat(data["expires_at"].replace("Z", "+00:00")).timestamp()
            if self._expires <= time.time() + 60:
                raise ValueError("Token expires too soon")
            self._token = data["token"]
            return self._token

    async def issue(self, number):
        if type(number) is not int or number < 1:
            raise ValueError("issue_number must be a positive integer")
        async with httpx.AsyncClient(timeout=30, follow_redirects=False, transport=self.transport) as http:
            # A revoked token is reissued once; do not retry permission/rate-limit failures.
            for attempt in range(2):
                token = await self.token(http)
                response = await http.get(f"{API}/repos/{self.repository}/issues/{number}", headers=headers(token))
                if response.status_code == 401:
                    async with self._lock:
                        if self._token == token:
                            self._token, self._expires = None, 0
                    if attempt == 0:
                        continue
                data = check(response, 200, "issue retrieval")
                break
        if "pull_request" in data:
            return {"status": "not_an_issue"}
        return {"status": "ok", "auth_mode": "github_app_installation",
                "installation_id": self.installation_id, "repository": self.repository,
                "number": data["number"], "title": data["title"], "body": data.get("body") or "",
                "state": data["state"], "url": data["html_url"]}
