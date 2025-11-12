import csv
import re
import sys
from pathlib import Path
from secrets import choice
from string import ascii_letters, digits, punctuation

def generate_password(length: int = 12) -> str:
    """
    비밀번호 생성기
    """
    alphabet = ascii_letters + digits + punctuation
    return "".join(choice(alphabet) for _ in range(length))


def guess_columns(headers):
    """
    흔한 헤더명을 기준으로 '이름'과 '학과' 계열 컬럼을 추정.
    """
    name_col = None
    dept_col = None

    # 이름 후보: 정확히 '이름' 우선, 없으면 '성명', '학생명', '신청자명' 등 포함
    name_priority = ['이름']
    dept_keywords = ['소속 학과', '학과', '전공', '학부', '학과(전공)']

    # 정확 일치 우선
    for h in headers:
        if h.strip() in name_priority and name_col is None:
            name_col = h
        if h.strip() in dept_keywords and dept_col is None:
            dept_col = h

    # 포함 검색(백업)
    if name_col is None:
        for h in headers:
            if '이름' in h or '성명' in h or '학생' in h:
                name_col = h
                break
    if dept_col is None:
        for h in headers:
            if any(k in h for k in ['소속 학과', '학과', '전공', '학부']):
                dept_col = h
                break

    return name_col, dept_col

_tid_re = re.compile(r'^([A-Za-z]*)(\d+)$')

def make_tid_counter(start_tid: str):
    """
    시작 TID 문자열(예: 't000001')을 받아 다음 값들을 순차 생성하는 클로저 반환.
    접두사/자릿수는 시작값을 따라감. (예: XYZ0012 → XYZ0013 …)
    """
    m = _tid_re.match(start_tid)
    if not m:
        raise ValueError(f"tid 형식이 잘못되었습니다: {start_tid!r} (예: t000001)")
    prefix, digits = m.groups()
    width = len(digits)
    n = int(digits)

    def next_tid():
        nonlocal n
        val = f"{prefix}{n:0{width}d}"
        n += 1
        return val

    return next_tid

def convert(
    input_csv: Path,
    output_csv: Path,
    start_tid: str,
    password_len: int = 12,
    encoding: str = 'utf-8-sig',
):
    with input_csv.open('r', encoding=encoding, newline='') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        if not headers:
            print("[오류] 헤더가 없는 CSV입니다.", file=sys.stderr)
            sys.exit(1)

        # 컬럼 결정
        guessed_name, guessed_dept = guess_columns(headers)
        name_col = guessed_name
        dept_col = guessed_dept

        if not name_col or not dept_col:
            print(
                f"[오류] 이름/학과 컬럼을 찾지 못했습니다. "
                f"(감지된 헤더: {headers})",
                file=sys.stderr,
            )
            sys.exit(1)

        # TID 생성기
        next_tid = make_tid_counter(start_tid)

        # 출력 준비
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        with output_csv.open('w', encoding=encoding, newline='') as out:
            writer = csv.writer(out)
            writer.writerow(['username', 'password', 'tid'])

            seen_usernames = set()
            row_idx = 1  # 데이터 기준(헤더 제외)

            for row in reader:
                row_idx += 1
                name = (row.get(name_col) or '').strip()
                dept = (row.get(dept_col) or '').strip().replace(" ", "")

                # 결측 처리
                if not name or not dept:
                    print(
                        f"[경고] {row_idx}행: 이름/학과 누락으로 건너뜀 "
                        f"(name={name!r}, dept={dept!r})",
                        file=sys.stderr,
                    )
                    continue

                username = f"{name}({dept})"

                # 중복 처리
                if username in seen_usernames:
                    print(
                        f"[경고] {row_idx}행: username 중복으로 건너뜀 → {username}",
                        file=sys.stderr,
                    )
                    continue
                seen_usernames.add(username)

                pwd = generate_password(password_len)
                tid = next_tid()

                writer.writerow([username, pwd, tid])

    print(
        f"[완료] 변환 성공: {output_csv}  "
        f"(start={start_tid}, name_col={name_col!r}, dept_col={dept_col!r})"
    )

def main():
    input_csv = input("응답 csv 파일의 이름을 알려주세요: ")
    output_csv = input("어떤 파일로 이름을 저장할까요? ")
    start_tid = input("tid 시작 번호를 입력하세요(t000001): ")
    password_len = 8
    encoding = 'utf-8-sig'
    convert(
        input_csv=Path(input_csv),
        output_csv=Path(output_csv),
        start_tid=start_tid,
        password_len=password_len,
        encoding=encoding,
    )

if __name__ == "__main__":
    main()
