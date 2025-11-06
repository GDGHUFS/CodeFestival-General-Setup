import sys
from pathlib import Path

def to_utf8_bom(file_path: str):
    path = Path(file_path)
    data = path.read_bytes()

    # 기존 파일 내용을 UTF-8로 디코딩 (깨진 바이트 처리)
    text = data.decode("utf-8", errors="replace")

    # BOM 포함 UTF-8로 다시 저장
    path.write_bytes(text.encode("utf-8-sig"))

    print(f"[OK] Converted to UTF-8 BOM → {path}")

if __name__ == "__main__":
    file_path = input("Enter the file path: ")
    to_utf8_bom(file_path)
