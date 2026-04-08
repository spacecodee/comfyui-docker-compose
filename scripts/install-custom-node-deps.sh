#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

load_env_vars() {
    local env_file=""
    if [[ -f "$ROOT_DIR/.env" ]]; then
        env_file="$ROOT_DIR/.env"
    elif [[ -f "$ROOT_DIR/.env.example" ]]; then
        env_file="$ROOT_DIR/.env.example"
    fi

    if [[ -z "$env_file" ]]; then
        return 0
    fi

    while IFS='=' read -r key value; do
        value="${value%$'\r'}"
        value="${value%\"}"
        value="${value#\"}"
        export "$key=$value"
    done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" || true)
}

resolve_path() {
    local path_value="$1"
    if [[ "$path_value" = /* ]]; then
        printf "%s" "$path_value"
    else
        printf "%s/%s" "$ROOT_DIR" "${path_value#./}"
    fi
}

manual_mode=false
if [[ "${1:-}" == "--manual" ]]; then
    manual_mode=true
    shift
fi

if [[ $# -gt 0 ]]; then
    echo "Unknown option: $1" >&2
    echo "Usage: ./scripts/install-custom-node-deps.sh [--manual]" >&2
    exit 1
fi

load_env_vars

auto_install="${COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS:-true}"
if [[ "$manual_mode" != "true" && "$auto_install" != "true" ]]; then
    echo "[custom-node-deps] auto install disabled (COMFY_AUTO_INSTALL_CUSTOM_NODE_DEPS=$auto_install)"
    exit 0
fi

comfy_dir="$(resolve_path "${COMFYUI_DIR:-./comfyui}")"
venv_dir="$(resolve_path "${COMFY_VENV_DIR:-./.venv}")"

if [[ -n "${COMFY_CUSTOM_NODES_DIR:-}" ]]; then
    custom_nodes_dir="$(resolve_path "${COMFY_CUSTOM_NODES_DIR}")"
else
    custom_nodes_dir="$comfy_dir/custom_nodes"
fi

if [[ -n "${COMFY_CUSTOM_NODE_DEPS_STATE_FILE:-}" ]]; then
    state_file="$(resolve_path "${COMFY_CUSTOM_NODE_DEPS_STATE_FILE}")"
else
    state_file="$comfy_dir/user/.cache/custom-node-deps-state.json"
fi

strict_mode="${COMFY_CUSTOM_NODE_DEPS_STRICT:-false}"
force_mode="${COMFY_CUSTOM_NODE_DEPS_FORCE:-false}"
python_bin="$venv_dir/bin/python"

if [[ ! -x "$python_bin" ]]; then
    echo "[custom-node-deps] python not found in virtual environment: $python_bin" >&2
    exit 1
fi

mkdir -p "$(dirname "$state_file")"

CUSTOM_NODES_DIR="$custom_nodes_dir" \
STATE_FILE="$state_file" \
STRICT_MODE="$strict_mode" \
FORCE_MODE="$force_mode" \
"$python_bin" - <<'PY'
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import tomllib
except Exception:
    tomllib = None


def log(message: str) -> None:
    print(f"[custom-node-deps] {message}")


def pip_install(args: list[str]) -> tuple[bool, str]:
    cmd = [sys.executable, "-s", "-m", "pip", "install", *args]
    log(f"running: {' '.join(cmd)}")
    result = subprocess.run(cmd)
    if result.returncode == 0:
        return True, ""
    return False, f"command failed ({result.returncode}): {' '.join(cmd)}"


custom_nodes_dir = Path(os.environ["CUSTOM_NODES_DIR"])
state_file = Path(os.environ["STATE_FILE"])
strict_mode = os.environ.get("STRICT_MODE", "false") == "true"
force_mode = os.environ.get("FORCE_MODE", "false") == "true"

if not custom_nodes_dir.exists():
    log(f"custom nodes directory not found: {custom_nodes_dir}")
    raise SystemExit(0)

node_dirs = sorted(
    p for p in custom_nodes_dir.iterdir() if p.is_dir() and not p.name.startswith(".")
)

manifests: list[tuple[str, Path, Path]] = []

for node_dir in node_dirs:
    req_files: list[Path] = []
    root_requirements = node_dir / "requirements.txt"
    if root_requirements.is_file():
        req_files.append(root_requirements)

    for pattern in ("requirements-*.txt", "requirements_*.txt"):
        req_files.extend(sorted(node_dir.glob(pattern)))

    seen_req: set[str] = set()
    for req_file in req_files:
        req_key = str(req_file.resolve())
        if req_key in seen_req:
            continue
        seen_req.add(req_key)
        manifests.append(("requirements", req_file, node_dir))

    pyproject_file = node_dir / "pyproject.toml"
    if pyproject_file.is_file():
        manifests.append(("pyproject", pyproject_file, node_dir))

if not manifests:
    log("no dependency manifests found in custom nodes")
    raise SystemExit(0)

state_hash = hashlib.sha256()
for manifest_type, manifest_path, _ in manifests:
    rel = manifest_path.relative_to(custom_nodes_dir)
    state_hash.update(manifest_type.encode("utf-8"))
    state_hash.update(b"\0")
    state_hash.update(str(rel).encode("utf-8"))
    state_hash.update(b"\0")
    state_hash.update(manifest_path.read_bytes())
    state_hash.update(b"\0")

current_hash = state_hash.hexdigest()
previous_hash = None

if state_file.exists():
    try:
        previous_hash = json.loads(state_file.read_text(encoding="utf-8")).get("hash")
    except Exception as exc:
        log(f"warning: could not parse state file ({state_file}): {exc}")

if not force_mode and previous_hash == current_hash:
    log("dependency manifests unchanged; skipping install")
    raise SystemExit(0)

if force_mode:
    log("force mode enabled; reinstalling dependencies")
else:
    log("dependency manifests changed; installing custom node dependencies")

errors: list[str] = []
processed = 0

for manifest_type, manifest_path, node_dir in manifests:
    node_label = node_dir.name
    rel = manifest_path.relative_to(custom_nodes_dir)

    if manifest_type == "requirements":
        log(f"installing requirements for {node_label}: {rel}")
        ok, error = pip_install(["-r", str(manifest_path)])
        processed += 1
        if not ok:
            errors.append(error)
            if strict_mode:
                break
        continue

    if manifest_type == "pyproject":
        if tomllib is None:
            msg = "tomllib unavailable, cannot parse pyproject.toml"
            errors.append(msg)
            if strict_mode:
                break
            log(f"warning: {msg}")
            continue

        try:
            data = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception as exc:
            msg = f"failed to parse {rel}: {exc}"
            errors.append(msg)
            if strict_mode:
                break
            log(f"warning: {msg}")
            continue

        dependencies = data.get("project", {}).get("dependencies", [])
        deps: list[str] = [
            dep.strip()
            for dep in dependencies
            if isinstance(dep, str) and dep.strip()
        ]

        if not deps:
            log(f"no [project].dependencies in {rel}; skipping")
            continue

        log(f"installing pyproject dependencies for {node_label}: {rel}")
        ok, error = pip_install(deps)
        processed += 1
        if not ok:
            errors.append(error)
            if strict_mode:
                break

if errors:
    for error in errors:
        log(f"warning: {error}")
    if strict_mode:
        log("strict mode enabled; failing startup due to dependency installation errors")
        raise SystemExit(1)
    log("dependency installation had warnings; state file not updated so startup will retry next run")
    raise SystemExit(0)

payload = {
    "hash": current_hash,
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "manifests": [
        {
            "type": manifest_type,
            "path": str(manifest_path.relative_to(custom_nodes_dir)),
        }
        for manifest_type, manifest_path, _ in manifests
    ],
}
state_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
log(f"dependency installation complete (processed manifests: {processed})")
log(f"state updated: {state_file}")
PY
