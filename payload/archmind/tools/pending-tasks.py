#!/usr/bin/env python3
"""Display and manage ArchMind maintenance tasks."""

from __future__ import annotations

import argparse
import json
import sys

from maintenance_state import clear_resolved, load_tasks, resolve_task, upsert_task


def display(include_resolved=False) -> int:
    tasks = load_tasks()
    visible = tasks if include_resolved else [task for task in tasks if not task["resolved"]]
    print("ArchMind Pending Tasks\n")
    if not visible:
        print("No pending maintenance tasks.")
        return 0
    order = {"critical": 0, "warning": 1, "info": 2}
    visible.sort(key=lambda item: (item["resolved"], order[item["severity"]], item["created_at"], item["id"]))
    for index, task in enumerate(visible, 1):
        state = "resolved" if task["resolved"] else task["severity"]
        print(f"{index}. [{state.upper()}] {task['title']}")
        if task["detail"]:
            print(f"   {task['detail']}")
        print(f"   ID: {task['id']} | Source: {task['source']} | Updated: {task['updated_at'] or 'unknown'}")
        print()
    return 1 if any(not task["resolved"] and task["severity"] == "critical" for task in visible) else 0


def interactive() -> int:
    display(include_resolved=True)
    tasks = load_tasks()
    pending = [task for task in tasks if not task["resolved"]]
    resolved = [task for task in tasks if task["resolved"]]
    print("1) Mark one pending task as reviewed/completed")
    print("2) Clear resolved task history")
    print("0) Exit")
    choice = input("\nChoice: ").strip()
    if choice == "1" and pending:
        for index, task in enumerate(pending, 1):
            print(f"{index}) {task['title']} [{task['id']}]")
        selected = input("Task number: ").strip()
        if selected.isdigit() and 1 <= int(selected) <= len(pending):
            task = pending[int(selected) - 1]
            confirmation = input(f"Type DONE to resolve {task['id']}: ").strip()
            if confirmation == "DONE":
                resolve_task(task["id"])
                print("Task marked as resolved. Update Guardian may reopen it if the condition remains.")
                return 0
        print("No task was resolved.")
    elif choice == "2" and resolved:
        answer = input("Type CLEAR to remove resolved history: ").strip()
        if answer == "CLEAR":
            print(f"Removed {clear_resolved()} resolved task record(s).")
        else:
            print("No task history was removed.")
    else:
        print("No task changes made.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="include resolved tasks")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--interactive", action="store_true")
    parser.add_argument("--resolve", metavar="ID")
    parser.add_argument("--clear-resolved", action="store_true")
    parser.add_argument("--add", metavar="ID")
    parser.add_argument("--title", default="Maintenance task")
    parser.add_argument("--detail", default="")
    parser.add_argument("--severity", choices=("info", "warning", "critical"), default="warning")
    parser.add_argument("--source", default="Manual")
    args = parser.parse_args()
    try:
        if args.add:
            upsert_task(args.add, args.title, args.detail, args.severity, args.source)
            print(f"Task recorded: {args.add}")
            return 0
        if args.resolve:
            print("Task resolved." if resolve_task(args.resolve) else "Task was already resolved or not found.")
            return 0
        if args.clear_resolved:
            print(f"Removed {clear_resolved()} resolved task record(s).")
            return 0
        if args.summary:
            tasks = [task for task in load_tasks() if not task["resolved"]]
            critical = sum(task["severity"] == "critical" for task in tasks)
            print(f"{len(tasks)} {critical}")
            return 0
        if args.json:
            print(json.dumps(load_tasks(), ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        return interactive() if args.interactive else display(args.all)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Task state unavailable: {error}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. No task history was removed.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
