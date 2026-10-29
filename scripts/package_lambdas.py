"""Create deterministic local function ZIPs; never upload or invoke AWS APIs.

The Lambda Python runtime supplies boto3. This package contains only pure Python
project code; runtime boto3 version is an explicit deployment dependency.
"""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".local" / "artifacts"
OUT.mkdir(parents=True, exist_ok=True)
for function in ("publisher", "aggregator", "query"):
    files = ["backend/__init__.py", "backend/common/__init__.py", "backend/common/aws.py",
             "backend/common/model.py", "backend/functions/__init__.py", f"backend/functions/{function}.py"]
    with ZipFile(OUT / f"{function}.zip", "w", compression=ZIP_DEFLATED) as package:
        for name in sorted(files):
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            package.writestr(info, (ROOT / name).read_bytes())
    print(f"Built local package: {function}.zip")
