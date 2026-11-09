#!/usr/bin/env python3
"""Collecteur du widget Projets.

Analogie: c'est le facteur du système. Il passe voir chaque projet, relève
l'avancement et dépose une seule lettre (projects.json) que le widget lit.
Le widget ne va jamais fouiller dans les projets lui-même.

Aucune dépendance à installer: Python 3.8+ et git suffisent.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

SCHEMA_VERSION = 1

# Où le widget va chercher le fichier par défaut
DEFAULT_OUT = Path.home() / "Library" / "Application Support" / "DeskWidgets" / "projects.json"

# Valeurs utilisées quand le fichier de configuration n'en donne pas
DEFAULT_CONFIG = {
    "roots": ["~/projets dev"],
    "exclude": [],
    "markers": [".git", "contexte.md", "README.md", "JOURNAL.md", "package.json", "TACHES.md"],
    "task_files": ["TACHES.md", "TODO.md", "TASKS.md", "ROADMAP.md", "contexte.md"],
    "activity_files": ["JOURNAL.md"],
    "display_names": {},
    "thresholds_days": {"active": 7, "quiet": 30},
}

# Une case Markdown: "- [ ] texte" ou "- [x] texte" (liste à puces ou numérotée)
CHECKBOX = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s+(.*\S)\s*$")
# Début ou fin d'un bloc de code, dont les cases ne comptent pas
FENCE = re.compile(r"^\s*(```|~~~)")
# Le tiret long est écrit par son code pour garder ce fichier sans ce caractère
LONG_DASH = " \u2014 "
MEDIUM_DASH = " \u2013 "


def load_config(path: Optional[Path]) -> dict:
    """Lit la configuration et complète avec les valeurs par défaut."""
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    if path is not None and path.exists():
        user = json.loads(path.read_text(encoding="utf-8"))
        for key, value in user.items():
            if key.startswith("_"):
                continue
            if isinstance(value, dict) and isinstance(config.get(key), dict):
                config[key].update(value)
            else:
                config[key] = value
    return config


def clean_label(label: str, limit: int = 100) -> str:
    """Rend le texte d'une tâche lisible sur une ligne de widget."""
    label = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", label)  # liens: on garde le texte
    label = label.replace("`", "").replace("**", "").replace("*", "")
    for dash in (LONG_DASH, MEDIUM_DASH):
        if dash in label:
            label = label.split(dash, 1)[0]
    # On retire les parenthèses de fin comme "(Stage 2, J2)"
    while True:
        shorter = re.sub(r"\s*\([^()]*\)\s*$", "", label)
        if shorter == label:
            break
        label = shorter
    label = label.strip()
    if len(label) > limit:
        label = label[: limit - 1].rstrip() + "…"
    return label


def read_tasks(path: Path) -> Tuple[int, int, Optional[str]]:
    """Compte les cases cochées et ouvertes d'un fichier, et repère la prochaine tâche."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0, 0, None
    done = 0
    total = 0
    next_task = None
    in_code = False
    for line in text.splitlines():
        if FENCE.match(line):
            in_code = not in_code
            continue
        if in_code:
            continue
        match = CHECKBOX.match(line)
        if not match:
            continue
        mark, label = match.group(1), match.group(2)
        if label.startswith("~~"):
            continue  # tâche abandonnée (barrée), elle ne compte pas
        total += 1
        if mark.lower() == "x":
            done += 1
        elif next_task is None:
            next_task = clean_label(label)
    return done, total, next_task


def run_git(repo: Path, *args: str) -> Optional[str]:
    """Lance une commande git en lecture seule, renvoie None si elle échoue."""
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")  # ne pas gêner un git lancé par toi
    try:
        result = subprocess.run(
            ["git", "-C", str(repo)] + list(args),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def parse_iso(value: str) -> Optional[datetime]:
    """Transforme une date ISO 8601 en datetime avec fuseau."""
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.astimezone()
    return parsed


def to_iso(moment: datetime) -> str:
    """Écrit une date au format attendu par le widget (secondes, avec fuseau)."""
    return moment.astimezone().replace(microsecond=0).isoformat()


def git_info(repo: Path) -> Optional[dict]:
    """Relève le dernier commit, la branche et le nombre de fichiers modifiés."""
    if not (repo / ".git").exists():
        return None
    info = {"commit": None, "branch": None, "dirty": None}
    log = run_git(repo, "log", "-1", "--format=%cI%x1f%s")
    if log and "\x1f" in log:
        date_text, subject = log.strip().split("\x1f", 1)
        date = parse_iso(date_text)
        if date is not None:
            info["commit"] = {"subject": subject.strip(), "date": date}
    branch = run_git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    if branch:
        info["branch"] = branch.strip()
    status = run_git(repo, "status", "--porcelain")
    if status is not None:
        info["dirty"] = len([line for line in status.splitlines() if line.strip()])
    return info


def file_moment(path: Path) -> Optional[datetime]:
    """Date de dernière modification d'un fichier."""
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    except OSError:
        return None


def find_projects(config: dict) -> List[Path]:
    """Liste les dossiers qui ressemblent à un projet dans les dossiers racines."""
    found = []
    excluded = set(config["exclude"])
    for root_text in config["roots"]:
        root = Path(root_text).expanduser()
        if not root.is_dir():
            continue
        for child in sorted(root.iterdir()):
            if child.name.startswith(".") or child.name in excluded or not child.is_dir():
                continue
            if any((child / marker).exists() for marker in config["markers"]):
                found.append(child)
    return found


def status_for(last: Optional[datetime], now: datetime, thresholds: Dict[str, int]) -> str:
    """Classe le projet selon le temps écoulé depuis sa dernière activité."""
    if last is None:
        return "unknown"
    days = (now - last).total_seconds() / 86400
    if days <= thresholds["active"]:
        return "active"
    if days <= thresholds["quiet"]:
        return "quiet"
    return "dormant"


def collect_project(path: Path, config: dict, now: datetime) -> dict:
    """Construit la fiche d'un projet."""
    done = total = 0
    next_task = None
    source = None
    candidates = []  # dates qui comptent comme de l'activité

    # Avancement: le premier fichier de tâches qui contient des cases
    for name in config["task_files"]:
        file = path / name
        if not file.is_file():
            continue
        file_done, file_total, file_next = read_tasks(file)
        if file_total > 0:
            done, total, next_task, source = file_done, file_total, file_next, name
            moment = file_moment(file)
            if moment:
                candidates.append(moment)
            break

    for name in config["activity_files"]:
        moment = file_moment(path / name)
        if moment:
            candidates.append(moment)

    git = git_info(path)
    commit = None
    if git and git["commit"]:
        commit = git["commit"]
        candidates.append(commit["date"])

    last = max(candidates) if candidates else None
    progress = round(done / total, 4) if total > 0 else None

    return {
        "id": re.sub(r"[^a-z0-9]+", "-", path.name.lower()).strip("-"),
        "name": config["display_names"].get(path.name, path.name),
        "path": str(path),
        "status": status_for(last, now, config["thresholds_days"]),
        "progress": progress,
        "tasks_done": done if total > 0 else None,
        "tasks_total": total if total > 0 else None,
        "next_task": next_task,
        "progress_source": source,
        "last_activity": to_iso(last) if last else None,
        "last_commit": {"subject": commit["subject"], "date": to_iso(commit["date"])} if commit else None,
        "branch": git["branch"] if git else None,
        "dirty_files": git["dirty"] if git else None,
    }


def build_feed(config: dict, now: datetime) -> dict:
    """Assemble le fichier final: résumé puis liste des projets, du plus récent au plus ancien."""
    projects = [collect_project(path, config, now) for path in find_projects(config)]
    projects.sort(key=lambda p: (p["last_activity"] is None, _neg(p["last_activity"]), p["name"].lower()))
    with_progress = [p["progress"] for p in projects if p["progress"] is not None]
    counts = {name: sum(1 for p in projects if p["status"] == name) for name in ("active", "quiet", "dormant", "unknown")}
    return {
        "schema_version": SCHEMA_VERSION,
        "widget": "projects",
        "generated_at": to_iso(now),
        "summary": {
            "total": len(projects),
            "active": counts["active"],
            "quiet": counts["quiet"],
            "dormant": counts["dormant"],
            "unknown": counts["unknown"],
            "average_progress": round(sum(with_progress) / len(with_progress), 4) if with_progress else None,
        },
        "projects": projects,
    }


def _neg(iso_text: Optional[str]) -> float:
    """Clé de tri: les dates récentes d'abord."""
    if not iso_text:
        return 0.0
    parsed = parse_iso(iso_text)
    return -parsed.timestamp() if parsed else 0.0


def write_atomic(feed: dict, out: Path) -> None:
    """Écrit le JSON dans un fichier temporaire puis le renomme, pour que le widget ne lise jamais un fichier à moitié écrit."""
    out.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(dir=str(out.parent), prefix=".projects-", suffix=".tmp")
    with os.fdopen(handle, "w", encoding="utf-8") as tmp:
        json.dump(feed, tmp, ensure_ascii=False, indent=2)
        tmp.write("\n")
    os.replace(tmp_name, str(out))


def print_table(feed: dict) -> None:
    """Affiche un tableau lisible dans le terminal (option --verbose)."""
    for p in feed["projects"]:
        percent = "  --" if p["progress"] is None else "{:3.0f}%".format(p["progress"] * 100)
        tasks = "" if p["tasks_total"] is None else "{}/{}".format(p["tasks_done"], p["tasks_total"])
        print("{:<8} {} {:>9}  {}".format(p["status"], percent, tasks, p["name"]), file=sys.stderr)


def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Génère projects.json pour le widget Projets.")
    parser.add_argument("--config", type=Path, default=here.parent / "config" / "projects.json")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--stdout", action="store_true", help="affiche le JSON au lieu de l'écrire")
    parser.add_argument("--verbose", action="store_true", help="affiche un résumé lisible")
    args = parser.parse_args()

    config = load_config(args.config)
    feed = build_feed(config, datetime.now(timezone.utc))

    if args.stdout:
        json.dump(feed, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        write_atomic(feed, args.out)
    if args.verbose:
        print_table(feed)
        if not args.stdout:
            print("Écrit: {}".format(args.out), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
