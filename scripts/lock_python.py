"""Record installed runtime dependencies for Linux, plus local test tooling.

Run only after dependency resolution. Does not contact AWS or install packages.
"""
import importlib.metadata as metadata
from pathlib import Path

from packaging.markers import default_environment
from packaging.requirements import Requirement

ROOT = Path(__file__).resolve().parents[1]
environment = {**default_environment(), "os_name": "posix", "sys_platform": "linux", "platform_system": "Linux", "extra": ""}
resolved = {}


def visit(name):
    distribution = metadata.distribution(name)
    canonical = distribution.metadata["Name"]
    if canonical in resolved:
        return
    resolved[canonical] = distribution.version
    for value in distribution.requires or []:
        requirement = Requirement(value)
        if not requirement.marker or requirement.marker.evaluate(environment):
            visit(requirement.name)


for name in ("boto3", "fastapi", "uvicorn", "redis"):
    visit(name)
ROOT.joinpath("requirements.lock").write_text(
    "# Resolved runtime dependencies for Python 3.12 / Linux.\n" +
    "\n".join(f"{name}=={version}" for name, version in sorted(resolved.items(), key=lambda item: item[0].lower())) + "\n")
print(f"Locked {len(resolved)} runtime packages")
