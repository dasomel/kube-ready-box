# HCP Credentials Setup & Rotation

> Vagrant Cloud(HCP Vagrant Registry) 게시용 Service Principal 키 발급 및 GitHub Secrets 갱신 절차.

## 배경

GitHub Actions의 `Publish to Vagrant Cloud` 단계는 HCP OAuth client_credentials grant로 인증합니다. 키가 무효/회전/삭제되면 다음 오류가 발생합니다:

```
OAuth2::Error: unauthorized: Authentication failed.
{"error":"unauthorized","error_description":"Authentication failed."}
```

호출 스택은 `vagrant_cloud-3.1.3/auth.rb:128 refresh_token!` → `oauth2/client.rb:174 request`. 추가로 `wrong number of arguments (given 1, expected 2)` 메시지가 보일 수 있는데, 이는 `vagrant_cloud` gem의 에러 출력 버그이며 **실제 원인은 위의 401 unauthorized**입니다.

## 사전 준비

| 항목 | 내용 |
|------|------|
| HCP CLI | `brew install hashicorp/tap/hcp` (macOS) |
| GitHub CLI | `gh auth login` 으로 repo 권한 |
| HCP Service Principal | `vagrant-registry-publisher` (project `41954172-375b-4048-a75e-0140aaa89474`) |
| 키 quota | SP당 최대 2개 |

## 절차

### 1. HCP에 사람 계정으로 로그인

> Service Principal 자격으로는 키를 발급할 수 없습니다 (`permission denied`). 반드시 사람 계정으로 로그인해야 합니다.

```bash
hcp auth logout      # 기존 SP 세션 종료
hcp auth login       # 브라우저 OAuth
hcp profile display  # 현재 organization/project 확인
```

### 2. 기존 키 목록 확인

```bash
hcp iam sp keys list vagrant-registry-publisher
```

출력 예:

```
Resource Name: iam/project/.../service-principal/vagrant-registry-publisher/key/<id1>
Client ID:     <id1>
Created At:    2026-05-03T12:03:43.135Z
---
Resource Name: iam/project/.../service-principal/vagrant-registry-publisher/key/<id2>
Client ID:     <id2>
Created At:    2026-05-01T01:57:52.580Z
```

### 3. 오래된 키 삭제 (quota 확보)

SP당 최대 2개이므로 새 키 발급 전 오래된 키를 정리합니다.

```bash
hcp iam sp keys delete \
  iam/project/41954172-375b-4048-a75e-0140aaa89474/service-principal/vagrant-registry-publisher/key/<OLD_KEY_ID>
```

> **주의**: 삭제 직후 해당 키로 인증 중인 워커가 있다면 즉시 실패합니다. 활성 빌드가 없는지 확인하세요.

### 4. 새 키 발급 (cred 파일로 저장)

`--output-cred-file`을 사용해 터미널과 shell history에 secret이 노출되지 않도록 합니다.

```bash
hcp iam sp keys create vagrant-registry-publisher \
  --output-cred-file=/tmp/hcp-cred.json
```

cred 파일 형식:

```json
{
  "scheme": "service_principal_creds",
  "workload": {
    "client_id": "<32자리>",
    "client_secret": "<64자리>"
  }
}
```

(실제 키 위치는 HCP CLI 버전에 따라 `client_id`/`client_secret` 또는 `oauth.client_id`/`oauth.client_secret`. `jq`의 `//` 폴백으로 흡수.)

### 5. 자격증명 검증

GitHub Secrets에 주입하기 **전에** 토큰 발급이 되는지 확인합니다.

```bash
CID=$(jq -r '.client_id // .oauth.client_id' /tmp/hcp-cred.json)
CSEC=$(jq -r '.client_secret // .oauth.client_secret' /tmp/hcp-cred.json)

curl -s -X POST https://auth.idp.hashicorp.com/oauth2/token \
  -d grant_type=client_credentials \
  -d client_id="$CID" \
  -d client_secret="$CSEC" \
  -d audience=https://api.hashicorp.cloud \
  | jq 'if .access_token then {ok: true, expires_in, token_type} else . end'
```

성공 시:

```json
{ "ok": true, "expires_in": 3600, "token_type": "Bearer" }
```

`unauthorized`가 나오면 SP에 Vagrant Registry 게시 권한(`Contributor` 이상)이 부여되어 있는지 확인.

### 6. GitHub Secrets 갱신

`--body -`로 stdin 입력을 받아 history에 평문이 남지 않도록 합니다.

```bash
printf '%s' "$CID"  | gh secret set HCP_CLIENT_ID     --repo dasomel/kube-ready-box --body -
printf '%s' "$CSEC" | gh secret set HCP_CLIENT_SECRET --repo dasomel/kube-ready-box --body -

gh secret list --repo dasomel/kube-ready-box | grep HCP_
```

### 7. cred 파일 삭제

```bash
rm -f /tmp/hcp-cred.json
unset CID CSEC
```

### 8. 워크플로우 재실행

```bash
gh workflow run build-amd64.yml --repo dasomel/kube-ready-box
gh workflow run build-arm64.yml --repo dasomel/kube-ready-box   # 필요 시

gh run watch --repo dasomel/kube-ready-box
```

`Publish to Vagrant Cloud` 단계가 통과하면 완료.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `permission denied` (key create) | SP 자격으로 로그인됨 | `hcp auth login`으로 사람 계정 재로그인 |
| `max service principal key quota per principal reached` | 키 ≥2개 | 오래된 키 `hcp iam sp keys delete`로 정리 |
| `unauthorized: Authentication failed` (workflow) | GH Secret 값이 stale 또는 SP 권한 부족 | 5단계 검증 → 6단계 재주입, HCP IAM에서 역할 확인 |
| `wrong number of arguments (given 1, expected 2)` | `vagrant_cloud-3.1.3` gem의 에러 출력 버그 | 무시. 실제 원인은 그 위/아래의 401 메시지 |

## 보안 노트

- cred 파일은 발급 후 즉시 삭제 (8단계 직후).
- `--body -` + `printf` 조합으로 secret이 shell history에 남지 않도록 함 (`set -o history; HISTFILE=/dev/null`도 권장).
- 키 회전 시 항상 **새 키 발급 → GH Secret 갱신 → 검증 → 오래된 키 삭제** 순서가 안전 (롤백 가능).
- 다만 HCP는 SP당 최대 2개 quota이므로 본 문서는 quota 부족 시 **오래된 키를 먼저 삭제**하는 흐름을 따름. 활성 워크로드가 없는지 반드시 확인.

## 관련 파일

- `.github/workflows/build-amd64.yml` — Publish step (`HCP_CLIENT_ID`, `HCP_CLIENT_SECRET` 사용)
- `.github/workflows/build-arm64.yml` — 동일
- [VAGRANT_CLOUD.md](VAGRANT_CLOUD.md) — Vagrant Cloud 일반 사용법
