"""Prepare coding copies and export checked OBS performance data. Python standard library only.

Never edits controller records. Auxiliary estimates are retained in the run, and
are never used to fill missing video measurements or subjective responses.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import statistics

IDENTITY = ("session_id", "mode", "participant", "group", "block", "condition", "orientation", "tab_load",
            "content_set", "trial", "target_id", "target_title", "is_repeat", "target_task_position",
            "task_tab_count", "visible_tab_count")
VIDEO = ("controller_status", "video_status", "video_file", "video_start_frame", "video_target_frame",
         "frame_rate", "retrieval_time_s", "total_tab_switches", "incorrect_selections",
         "first_selection_correct", "no_selection", "technical_loss", "coder", "notes")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or len(set(reader.fieldnames)) != len(reader.fieldnames):
            raise ValueError(f"Missing/duplicate CSV header: {path}")
        result = list(reader)
        if any(None in row or any(v is None for v in row.values()) for row in result):
            raise ValueError(f"Malformed CSV row: {path}")
        return result


def write_csv(path: Path, rows: list[dict], columns: tuple | list) -> None:
    with path.open("x", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def number(value: str | None, label: str, *, integer=False, low=0, high=math.inf):
    if value is None or value.strip() == "":
        return None
    try:
        n = float(value)
    except ValueError as exc:
        raise ValueError(f"{label}: expected a number") from exc
    if not math.isfinite(n) or not low <= n <= high or (integer and not n.is_integer()):
        raise ValueError(f"{label}: invalid value {value!r}")
    return int(n) if integer else n


def boolean(value: str | None, label: str):
    if value is None or not value.strip():
        return None
    text = value.strip().lower()
    if text in ("1", "true"): return 1
    if text in ("0", "false"): return 0
    raise ValueError(f"{label}: use 1/0 or true/false")


def scheduled(meta: dict) -> list[dict]:
    result = []
    for bi, block in enumerate(meta["plan"], 1):
        seen = set()
        for ti, trial in enumerate(block["trials"], 1):
            row = {k: meta.get(k, "") for k in ("session_id", "mode", "participant", "group")}
            row.update(block=bi, condition=block["name"], orientation=block["orientation"],
                       tab_load=block["tabLoad"], content_set=block["contentSet"], trial=trial["id"],
                       target_id=trial["targetID"], target_title=trial["targetTitle"],
                       is_repeat=int(trial["targetID"] in seen),
                       target_task_position=block["taskOrder"].index(trial["path"]) + 1,
                       visible_tab_count=block["expectedTabCount"], task_tab_count=block["expectedTabCount"] - 1)
            seen.add(trial["targetID"])
            result.append(row)
    return result


def key(row: dict) -> tuple[str, str]:
    return str(row["block"]), str(row["trial"])


def indexed(rows: list[dict], expected: list[dict], meta: dict) -> dict:
    allowed = {key(r): r for r in expected}
    result = {}
    for row in rows:
        k = key(row)
        if k not in allowed or k in result:
            raise ValueError(f"Duplicate or unscheduled trial: {k}")
        for field in IDENTITY:
            if field in row and row[field] != "" and str(row[field]) != str(allowed[k].get(field, "")):
                raise ValueError(f"Identity mismatch for {k}: {field}")
        result[k] = row
    return result


def prepare(run: Path, out: Path) -> None:
    meta = json.loads((run / "session.json").read_text())
    plan = scheduled(meta)
    raw = indexed(read_csv(run / "trials_aux.csv"), plan, meta)
    out.mkdir(parents=True, exist_ok=False)
    video = []
    for row in plan:
        row = dict(row)
        row["controller_status"] = raw.get(key(row), {}).get("status", "no_terminal_outcome")
        video.append(row)
    write_csv(out / "video_coding.csv", video, IDENTITY + VIDEO)
    (out / "CODING_README.txt").write_text(
        "Analysis copy; preserve original logs and video. Do not edit identity columns.\n"
        "video_status: completed, timeout, interrupted, technical_loss, or not_exposed.\n"
        "Frame numbers: use one constant-rate source and its actual fps. RT=(target-start)/fps.\n"
        "Set technical_loss and no_selection from observable video, not controller status.\n"
        "Do not treat missing selections as incorrect or as zero selections.\n"
        "NASA-TLX remains in Google Forms. Join by participant code and condition.\n", encoding="utf-8")


def video_values(row: dict) -> dict:
    status = row.get("video_status", "").strip()
    if status not in ("", "completed", "timeout", "interrupted", "technical_loss", "not_exposed"):
        raise ValueError(f"Invalid video_status: {status}")
    result = {k: row.get(k, "") for k in VIDEO}
    # Blank means unreviewed, even if all controller estimates are available.
    result.update(measurement_source="OBS" if status else "uncoded", video_verified=0)
    if not status:
        if any(row.get(k, "") for k in VIDEO if k not in ("controller_status", "notes")):
            raise ValueError("Video measurements require video_status and coder")
        return result
    if status == "not_exposed":
        if any(row.get(k, "") for k in ("retrieval_time_s", "video_start_frame", "video_target_frame",
                                         "total_tab_switches", "incorrect_selections", "first_selection_correct")):
            raise ValueError("not_exposed cannot have trial measurements")
        return result
    if not row.get("coder", "").strip() or not row.get("video_file", "").strip():
        raise ValueError("Coded trials require coder and video_file")
    loss = boolean(row.get("technical_loss"), "technical_loss")
    no_selection = boolean(row.get("no_selection"), "no_selection")
    first = boolean(row.get("first_selection_correct"), "first_selection_correct")
    total = number(row.get("total_tab_switches"), "total_tab_switches", integer=True)
    wrong = number(row.get("incorrect_selections"), "incorrect_selections", integer=True)
    rt = number(row.get("retrieval_time_s"), "retrieval_time_s")
    start = number(row.get("video_start_frame"), "video_start_frame", integer=True)
    end = number(row.get("video_target_frame"), "video_target_frame", integer=True)
    fps = number(row.get("frame_rate"), "frame_rate", low=0.001)
    if loss is None: raise ValueError("Explicit technical_loss=0/1 is required")
    if status == "technical_loss" and loss != 1: raise ValueError("technical_loss status requires technical_loss=1")
    if status == "completed":
        if loss or no_selection != 0 or first is None or total is None or wrong is None:
            raise ValueError("Completed trials require observable selections and no technical loss")
        if total != wrong + 1 or (first == 1 and wrong != 0) or (first == 0 and wrong == 0):
            raise ValueError("Inconsistent completed-trial selection counts")
        if start is None or end is None or fps is None or end < start:
            raise ValueError("Completed trials require ordered start/target frames and actual frame rate")
        calculated = (end - start) / fps
        if rt is not None and not math.isclose(rt, calculated, abs_tol=1 / fps + 1e-9):
            raise ValueError("Entered RT disagrees with video frames by more than one frame")
        rt = calculated
    elif rt is not None or end is not None:
        raise ValueError("Incomplete trials must have blank RT and target frame")
    if no_selection == 1 and (total != 0 or wrong != 0 or first is not None):
        raise ValueError("no_selection requires zero selections and blank first-selection correctness")
    if status == "timeout" and not loss:
        if no_selection is None or total is None or wrong is None or total != wrong:
            raise ValueError("Observable timeout requires complete selection/no-selection coding")
        if no_selection == 0 and (total < 1 or first != 0):
            raise ValueError("Timeout with selections requires an incorrect first selection")
    result.update(retrieval_time_s=rt, total_tab_switches=total, incorrect_selections=wrong,
                  first_selection_correct=first, no_selection=no_selection, technical_loss=loss,
                  video_verified=1)
    return result


def export(run: Path, coding: Path, out: Path) -> None:
    meta = json.loads((run / "session.json").read_text())
    plan = scheduled(meta)
    coded = indexed(read_csv(coding / "video_coding.csv"), plan, meta)
    raw = indexed(read_csv(run / "trials_aux.csv"), plan, meta)
    if set(coded) != {key(r) for r in plan}: raise ValueError("Missing video coding rows; use prepare first")
    results = []
    for row in plan:
        coding_row = coded[key(row)]
        status = raw.get(key(row), {}).get("status", "no_terminal_outcome")
        if coding_row["controller_status"] != status: raise ValueError("Controller status was changed in coding sheet")
        if status != "no_terminal_outcome" and coding_row.get("video_status") == "not_exposed":
            raise ValueError("Raw exposed trial cannot be relabeled not_exposed")
        results.append({**row, **video_values(coding_row), "controller_status": status})
    summaries = []
    for bi, block in enumerate(meta["plan"], 1):
        rows = [r for r in results if r["block"] == bi]
        valid = [r for r in rows if r["video_verified"] == 1 and r["video_status"] in ("completed", "timeout") and r["technical_loss"] == 0]
        rt = [r["retrieval_time_s"] for r in valid if r["retrieval_time_s"] is not None]
        first = [r["first_selection_correct"] for r in valid if r["first_selection_correct"] is not None]
        selections = sum(r["total_tab_switches"] for r in valid)
        incorrect = sum(r["incorrect_selections"] for r in valid)
        summaries.append({**{k: rows[0][k] for k in IDENTITY[:9]}, "scheduled_trials": len(rows),
                          "coded_completed_or_timeout": len(valid), "completed_rt_n": len(rt),
                          "mean_retrieval_time_s": statistics.mean(rt) if rt else "",
                          "first_selection_n": len(first),
                          "first_selection_error_rate": 1 - statistics.mean(first) if first else "",
                          "observed_selection_error_rate": incorrect / selections if selections else "",
                          "total_selections": selections, "incorrect_selections": incorrect,
                          "timeouts": sum(r["video_status"] == "timeout" for r in valid),
                          "no_selection_trials": sum(r.get("no_selection") == 1 for r in valid),
                          "uncoded_trials": sum(not r["video_status"] for r in rows),
                          "not_exposed_trials": sum(r["video_status"] == "not_exposed" for r in rows),
                          "technical_loss_trials": sum(r.get("technical_loss") == 1 for r in rows),
                          "interrupted_trials": sum(r["video_status"] == "interrupted" for r in rows)})
    out.mkdir(parents=True, exist_ok=False)
    write_csv(out / "analysis_trials.csv", results, IDENTITY + VIDEO + ("measurement_source", "video_verified"))
    write_csv(out / "condition_summary.csv", summaries, list(summaries[0]))
    write_csv(out / "survey_join_keys.csv", summaries, IDENTITY[:9])
    (out / "EXPORT_README.txt").write_text(
        "Only OBS-coded trials enter performance summaries; no auxiliary substitution.\n"
        "RT uses completed trials only; timeouts retain observable selections.\n"
        "First-selection error excludes trials with no observed first selection; its denominator is first_selection_n.\n"
        "observed_selection_error_rate pools incorrect/total tab activations and is a different descriptive measure.\n"
        "Repeated targets remain included and are flagged for any prespecified sensitivity analysis.\n"
        "NASA-TLX is collected in Google Forms, outside this controller.\n"
        "Join Forms results using participant code AND condition, not row order.\n"
        "Missing video coding remains missing, not zero.\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "export"))
    parser.add_argument("run", type=Path)
    parser.add_argument("--coding", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "prepare": prepare(args.run, args.out)
        else:
            if args.coding is None: parser.error("export requires --coding")
            export(args.run, args.coding, args.out)
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, f"Encoding stopped: {exc}\n")
    print(f"Created {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
