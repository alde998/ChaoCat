#!/usr/bin/env python3
"""Fixed display calibration; native GIF pixels and timing stay untouched.

Compare anatomical landmarks at desktop scale, not total bounds (which include
tails, dust, shadows and airborne height). See exports/animation-audit.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "apps/macos/Assets/Behavior/catalog.json"
SPRINT_SCALE = 0.180842
JUMP_SCALE = 0.228432


def calibrate(catalog):
    for direction in ("right", "left"):
        sprint = catalog[f"rubbish-run-{direction}"]
        sprint.update(scale=SPRINT_SCALE, stride=round(179.78 * SPRINT_SCALE / 0.19036, 2))
        original = f"rubbish-run-{direction}"
        catalog[f"chase-run-{direction}"] = dict(sprint, displayVariantOf=original)
        jump = catalog[f"rubbish-jump-{direction}"]
        jump.update(scale=JUMP_SCALE, footX=760 if direction == "right" else 840, footY=875)
        # These three clips contain a cat far left of the nominal x=800
        # canvas center. Anchor its ground contact instead of the canvas.
        for phase, x, y in (("chase-enter", 620, 893), ("catch", 690, 894), ("chase-exit", 630, 892)):
            catalog[f"{phase}-{direction}"].update(footX=x if direction == "right" else 1600-x, footY=y)
    return catalog


if __name__ == "__main__":
    catalog = calibrate(json.loads(CATALOG.read_text()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
