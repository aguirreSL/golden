"""Download the public sound sets the SQAT validations use and check them byte for byte.

    python tools/fetch_sounds.py <dest>

<dest>/validation_SQAT_v1_0        Zenodo 10.5281/zenodo.7933206 (CC BY 4.0)
<dest>/AIAA-2020-2582_Sound_Files  NASA, AIAA paper 2020-2582

The SHA-256 values are those of the archives the Mac goldens were recorded from.
"""
import hashlib
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

SETS = [
    ("https://zenodo.org/records/7933206/files/validation_SQAT_v1_0.zip?download=1",
     "0643a34ea6fe261be4f7fc141c02516d2fe06ecbf96074ef3dddba42c00169ec", "."),
    ("https://stabservdata.larc.nasa.gov/flyover/Aviation2020/AIAA-2020-2582_Sound_Files.zip",
     "2dd2b200795a82113085f6a8adf4e2ee211c615ba19a9239b3457a10867a25a2", "AIAA-2020-2582_Sound_Files"),
]


def fetch(url, path):
    for attempt in range(5):  # Zenodo answers 504 now and then
        try:
            with urllib.request.urlopen(url, timeout=600) as r, open(path, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            return
        except OSError as e:
            print(f"retry {attempt + 1}: {e}", flush=True)
            time.sleep(30)
    sys.exit(f"download failed: {url}")


def main():
    dest = Path(sys.argv[1])
    dest.mkdir(parents=True, exist_ok=True)
    for url, sha, sub in SETS:
        z = dest / "archive.zip"
        fetch(url, z)
        got = hashlib.sha256(z.read_bytes()).hexdigest()
        if got != sha:
            sys.exit(f"{url}: sha256 {got}, expected {sha}")
        with zipfile.ZipFile(z) as a:
            a.extractall(dest / sub)
        z.unlink()
        print(f"ok {url}", flush=True)


if __name__ == "__main__":
    main()
