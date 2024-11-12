import datetime
from dataclasses import dataclass
from collections import defaultdict
import json
from pathlib import Path


@dataclass
class BuildStepTiming:
    name: str
    date: datetime.datetime
    delta: float


def find_and_load_logs(path="logs"):
    out = []
    for f in sorted(Path("logs").glob("*.json"), reverse=True):
        with open(f) as fin:
            out.append(json.load(fin))
    return out


def package_build_times(logs, skip_pip=True):
    out = defaultdict(list)
    for log in logs:
        for step in log["build_steps"]:
            if "packages" in step and skip_pip:
                continue
            if step["returncode"] != 0:
                continue
            name = step["name"]
            out[name].append(
                BuildStepTiming(
                    name,
                    datetime.datetime.fromtimestamp(step["start_time"]),
                    delta=step["stop_time"] - step["start_time"],
                )
            )
    return dict(out)


def plot_trace(ax, times, package, **kwargs):
    return ax.plot(
        *zip(*[(_.date, _.delta) for _ in times[package]]),
        "o",
        **{"label": package, **kwargs},
    )


def compare_build_times(ax, times, packages, **kwargs):
    ax.set_ylabel("build time [s]")
    ax.set_xlabel("date")
    for p in packages:
        plot_trace(ax, times, p, **kwargs)
    ax.legend()
