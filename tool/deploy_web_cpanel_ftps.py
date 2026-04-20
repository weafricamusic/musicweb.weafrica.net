#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import posixpath
import ssl
from ftplib import FTP_TLS, error_perm
from pathlib import Path


def env_or_required(name: str, required: bool = True, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if required and (value is None or value.strip() == ""):
        raise SystemExit(f"Missing required env var: {name}")
    return (value or "").strip()


def ensure_remote_dir(ftp: FTP_TLS, remote_dir: str) -> None:
    remote_dir = remote_dir.strip().rstrip("/")
    if not remote_dir:
        return
    parts = [p for p in remote_dir.split("/") if p]
    cwd = "/"
    for part in parts:
        cwd = posixpath.join(cwd, part)
        try:
            ftp.mkd(cwd)
        except error_perm as e:
            msg = str(e)
            if not ("File exists" in msg or msg.startswith("550")):
                raise


def list_remote_names(ftp: FTP_TLS, remote_dir: str) -> set[str]:
    names: set[str] = set()
    try:
        ftp.cwd(remote_dir)
        ftp.retrlines("NLST", names.add)
    except Exception:
        return set()
    return {n.split("/")[-1] for n in names if n and n not in (".", "..")}


def upload_tree(
    ftp: FTP_TLS,
    local_root: Path,
    remote_root: str,
    delete: bool,
) -> tuple[int, int]:
    uploaded_files = 0
    created_dirs = 0

    local_root = local_root.resolve()
    ensure_remote_dir(ftp, remote_root)

    for dirpath, dirnames, filenames in os.walk(local_root):
        local_dir = Path(dirpath)
        rel = local_dir.relative_to(local_root)
        remote_dir = remote_root if str(rel) == "." else posixpath.join(remote_root, rel.as_posix())

        ensure_remote_dir(ftp, remote_dir)

        if delete:
            local_entries = set(dirnames) | set(filenames)
            remote_entries = list_remote_names(ftp, remote_dir)
            stale = sorted(remote_entries - local_entries)
            for name in stale:
                candidate = posixpath.join(remote_dir, name)
                try:
                    ftp.delete(candidate)
                except Exception:
                    # Might be a directory; ignore for safety (non-recursive delete intentionally skipped)
                    pass

        for name in filenames:
            local_file = local_dir / name
            remote_file = posixpath.join(remote_dir, name)
            with local_file.open("rb") as f:
                ftp.storbinary(f"STOR {remote_file}", f)
            uploaded_files += 1

        created_dirs += len(dirnames)

    return uploaded_files, created_dirs


def main() -> None:
    parser = argparse.ArgumentParser(description="Deploy Flutter web build to cPanel using FTPS.")
    parser.add_argument("--host", default=os.getenv("CPANEL_FTP_HOST", ""), help="FTPS host")
    parser.add_argument("--port", type=int, default=int(os.getenv("CPANEL_FTP_PORT", "21")), help="FTPS port")
    parser.add_argument("--user", default=os.getenv("CPANEL_FTP_USER", ""), help="FTPS username")
    parser.add_argument("--password", default=os.getenv("CPANEL_FTP_PASSWORD", ""), help="FTPS password")
    parser.add_argument("--src", default=os.getenv("SRC_DIR", "build/web"), help="Local source directory")
    parser.add_argument(
        "--remote-dir",
        default=os.getenv("REMOTE_DIR", "/public_html/music"),
        help="Remote destination directory",
    )
    parser.add_argument("--delete", action="store_true", help="Delete stale remote files (files only)")
    parser.add_argument("--insecure", action="store_true", help="Disable TLS certificate validation")

    args = parser.parse_args()

    host = args.host.strip() or env_or_required("CPANEL_FTP_HOST")
    user = args.user.strip() or env_or_required("CPANEL_FTP_USER")
    password = args.password or env_or_required("CPANEL_FTP_PASSWORD")

    src = Path(args.src)
    if not src.is_dir():
        raise SystemExit(f"Source directory not found: {src}")

    tls_context = ssl.create_default_context()
    if args.insecure:
        tls_context.check_hostname = False
        tls_context.verify_mode = ssl.CERT_NONE

    ftp = FTP_TLS(context=tls_context)
    ftp.connect(host=host, port=args.port, timeout=20)
    ftp.login(user=user, passwd=password)
    ftp.prot_p()

    print(f"Connected to {host}:{args.port}")
    print(f"Uploading {src} -> {args.remote_dir}")

    uploaded, dirs = upload_tree(ftp, src, args.remote_dir, delete=args.delete)
    ftp.quit()

    print(f"Upload complete. Files uploaded: {uploaded}")
    print("Run verification:")
    print("  ./tool/verify_web_fcm_deploy.sh")


if __name__ == "__main__":
    main()
