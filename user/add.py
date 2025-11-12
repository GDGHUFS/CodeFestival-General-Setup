import csv
import json
import sys
import time
from typing import Dict, Any, Optional, Tuple, List
import requests

CSV_PATH = "./dummy2.csv" # 변경 필수
REQUEST_TIMEOUT = 20  # seconds

class ApiError(Exception):
    pass


def prompt_admin_and_target() -> Tuple[str, str, str, str, bool]:
    base_url = input(f"DOMjudge Base URL [예: https://ps.gdghufs.com]: ").strip()
    admin_user = input("Admin username: ").strip()
    admin_pass = input("Admin password: ").strip()
    cid = input("Contest ID (cid): ").strip()
    use_ip_strict = input("사용자별 IP 접속 제한을 하시겠습니까? [Y/N]: ").strip()
    if use_ip_strict.upper().startswith("Y"):
        use_ip_strict = True
    else:
        use_ip_strict = False
    if not (base_url and admin_user and admin_pass and cid):
        raise SystemExit("입력이 부족합니다. Base URL, 관리자 계정, 대회ID, 사용자별 접속 제한은 필수입니다.")
    return base_url.rstrip("/"), admin_user, admin_pass, cid, use_ip_strict


def new_session(admin_user: str, admin_pass: str) -> requests.Session:
    s = requests.Session()
    s.auth = (admin_user, admin_pass)  # HTTP Basic (OpenAPI securitySchemes.basicAuth)
    s.headers.update({"Accept": "application/json"})
    return s


def api_get(s: requests.Session, url: str, **kw) -> requests.Response:
    r = s.get(url, timeout=REQUEST_TIMEOUT, **kw)
    return r


def api_post_json(s: requests.Session, url: str, payload: Dict[str, Any], **kw) -> requests.Response:
    r = s.post(url, json=payload, timeout=REQUEST_TIMEOUT, **kw)
    return r


def load_csv(path: str) -> List[Dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        required = {"username", "password", "tid"}
        if not required.issubset(set([c.strip() for c in reader.fieldnames or []])):
            raise SystemExit(f"CSV 헤더에 username,password,tid가 모두 있어야 합니다. 현재 헤더: {reader.fieldnames}")
        rows = []
        for i, row in enumerate(reader, 1):
            username = (row.get("username") or "").strip()
            password = (row.get("password") or "")
            tid = (row.get("tid") or "").strip()
            if not (username and password and tid):
                print(f"{i}행 건너뜀: 필드 누락(username: {username}/password: {password}/tid: {tid})")
                continue
            rows.append({"username": username, "password": password, "tid": tid})
    return rows


def ping_api(s: requests.Session, base_url: str) -> None:
    """
    /api/v4/info 로 간단 확인
    인증 실패나 권한 부족 시 에러를 일으킴
    """
    url = f"{base_url}/api/v4/info"
    r = api_get(s, url)
    if r.status_code != 200:
        raise ApiError(f"API 접속/인증 실패: GET {url} -> {r.status_code} {r.text[:200]}")


def find_team_id_by_name(s: requests.Session, base_url: str, cid: str, team_name: str) -> Optional[str]:
    """
    /api/v4/contests/{cid}/teams 에서 이름 완전 일치 검색
    """
    url = f"{base_url}/api/v4/contests/{cid}/teams"
    r = api_get(s, url)
    if r.status_code != 200:
        raise ApiError(f"팀 목록 조회 실패: GET {url} -> {r.status_code} {r.text[:200]}")
    try:
        teams = r.json()
        for t in teams:
            if (t.get("name") or "").strip() == team_name:
                return str(t.get("id"))
    except Exception as e:
        raise ApiError(f"팀 목록 파싱 실패: {e}")
    return None


def ensure_team(s: requests.Session, base_url: str, cid: str, team_display_name: str, team_id: str) -> Tuple[
    str, bool, str]:
    """
    팀이 없으면 생성하고, 있으면 기존 팀 ID 반환.
    반환: (team_id, created_bool, message)
    """
    url_post = f"{base_url}/api/v4/teams"
    payload = {
        "id": team_id,
        "name": team_display_name,
        "display_name": team_display_name
        # AddTeam 스키마: id/icpc_id/label/organization_id 등 선택적: ps.gdghufs.com/api/doc
        # (필수 필드는 아님)
    }
    r = api_post_json(s, url_post, payload, params={"cid": cid})
    if r.status_code == 201:
        team = r.json()
        return str(team.get("id")), True, "created"

    # 중복 등으로 실패하면 이름 기준으로 재검색
    if r.status_code in (400, 409):
        existing_id = find_team_id_by_name(s, base_url, cid, team_display_name)
        if existing_id:
            print("이미 존재하는 team id가 조회되었습니다. 중복을 의심하십시오")
            return existing_id, False, "reused-existing"
        else:
            return "", False, f"create-failed({r.status_code}) {r.text[:200]}"

    return "", False, f"create-failed({r.status_code}) {r.text[:200]}"


def create_user_for_team(s: requests.Session, base_url: str, username: str, password: str, team_id: str, use_ip_strict: bool) -> Tuple[
    Optional[str], str]:
    """
    AddUser 스키마: username, name, roles 필수. team 역할을 부여하고 team_id 연결.
    """
    url = f"{base_url}/api/v4/users"
    if use_ip_strict:
        ip = input(f"{username}의 IP 주소를 입력하십시오: ").strip();
        payload = {
            "username": username,
            "name": username,
            "password": password,
            "team_id": str(team_id),
            "enabled": True,
            "ip": ip,
            "roles": ["team"],  # 참가자 역할
        }
    else:
        payload = {
            "username": username,
            "name": username,
            "password": password,
            "team_id": str(team_id),
            "enabled": True,
            "roles": ["team"],  # 참가자 역할
        }
    r = api_post_json(s, url, payload)
    if r.status_code == 201:
        try:
            user = r.json()
            return str(user.get("id")), "created"
        except Exception:
            return None, "created(parse-warn)"
    elif r.status_code == 400 and "already" in (r.text or "").lower():
        # username 중복 등
        return None, f"skipped-duplicate({r.status_code})"
    elif r.status_code in (401, 403):
        return None, f"auth-failed({r.status_code})"
    else:
        return None, f"create-failed({r.status_code}) {r.text[:200]}"


def main():
    base_url, admin_user, admin_pass, cid, use_ip_strict = prompt_admin_and_target()
    sess = new_session(admin_user, admin_pass)

    try:
        ping_api(sess, base_url)
    except Exception as e:
        print(f"API 점검 실패: {e}")
        sys.exit(2)

    participants = load_csv(CSV_PATH)
    if not participants:
        print("처리할 참가자가 없습니다.")
        return

    results = []
    print(f"{len(participants)}명 처리 시작... (cid={cid})")
    for i, p in enumerate(participants, 1):
        username, pw, tid = p["username"], p["password"], p["tid"]
        prefix = f"[{i}/{len(participants)}] {username} / {tid}"

        # 1) 팀 생성
        try:
            team_id, created_team, tmsg = ensure_team(sess, base_url, cid, username, tid)
            if not team_id:
                print(f"{prefix} → 팀 생성 실패: {tmsg}")
                results.append(
                    {"username": username, "name": username, "team_id": tid, "user_id": None, "team_status": tmsg,
                     "user_status": "skipped"})
                continue
        except Exception as e:
            print(f"{prefix} → 팀 처리 중 오류: {e}")
            results.append(
                {"username": username, "name": username, "team_id": tid, "user_id": None, "team_status": "exception",
                 "user_status": "skipped"})
            continue

        # 2) 유저 생성
        try:
            user_id, ustatus = create_user_for_team(sess, base_url, username, pw, team_id, use_ip_strict)
            ok = (ustatus.startswith("created"))
            mark = "✅" if ok else ("⚠️" if "duplicate" in ustatus else "❌")
            created_note = " (신규 팀)" if created_team else ""
            print(f"{prefix} → 팀ID={team_id}{created_note} / 사용자={mark} {ustatus}")
            results.append({"username": username, "name": username, "team_id": team_id, "user_id": user_id,
                            "team_status": ("created" if created_team else "reused"), "user_status": ustatus})
        except Exception as e:
            print(f"{prefix} → 사용자 생성 오류: {e}")
            results.append({"username": username, "name": username, "team_id": team_id, "user_id": None,
                            "team_status": ("created" if created_team else "reused"), "user_status": "exception"})

        # rate limit 방지용
        time.sleep(0.05)

    created_users = sum(1 for r in results if str(r["user_status"]).startswith("created"))
    duplicates = sum(1 for r in results if "duplicate" in str(r["user_status"]))
    failures = sum(1 for r in results if
                   r["user_status"] not in ("created", "created(parse-warn)") and "duplicate" not in str(
                       r["user_status"]))
    print("\n=== 처리 요약 ===")
    print(f"생성 성공: {created_users}, 중복(스킵): {duplicates}, 실패/예외: {failures}")

    try:
        out_path = "domjudge_provision_result.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"결과 파일: {out_path}")
    except Exception as e:
        print(f"⚠️ 결과 파일 저장 실패: {e}")


if __name__ == "__main__":
    main()
