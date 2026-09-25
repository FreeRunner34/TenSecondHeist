"""Fast authoring check mirroring the Swift rules. Xcode XCTest is the release gate."""
import json
import math
from pathlib import Path

LEVELS = Path(__file__).resolve().parents[1] / "TenSecondHeist/Resources/levels.json"
HEADINGS = {"north": (0, -1), "east": (1, 0), "south": (0, 1), "west": (-1, 0)}


def point(tile): return (tile["x"], tile["y"])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def delta(a, b): return (a[0] - b[0], a[1] - b[1])
def distance(a, b): return math.hypot(a[0] - b[0], a[1] - b[1])
def tile(p): return (math.floor(p[0] + .5), math.floor(p[1] + .5))
def floor(level, p):
    x, y = p
    return 0 <= y < len(level["map"]) and 0 <= x < len(level["map"][y]) and level["map"][y][x] != "#"


def direction(a, b):
    dx, dy = delta(b, a)
    if abs(dx) > abs(dy): return "east" if dx >= 0 else "west"
    return "south" if dy >= 0 else "north"


def seeing(level, origin, facing, target, reach, angle):
    dx, dy = delta(target, origin)
    length = math.hypot(dx, dy)
    if not .18 < length <= reach: return False
    forward = HEADINGS[facing]
    if (dx * forward[0] + dy * forward[1]) / length < math.cos(math.radians(angle)): return False
    samples = max(2, math.ceil(length * 16))
    return all(floor(level, tile((origin[0] + dx * i / samples, origin[1] + dy * i / samples))) for i in range(1, samples))


def script(actions, start):
    previous, clock, output = start, 0, []
    for action in actions:
        kind = action["kind"]
        end = point(action["at"]) if kind == "move" else previous
        ticks = action.get("ticks", 4) if kind == "wait" else 4 if kind == "hack" else 2
        output.append((action, clock, clock + ticks, previous, end))
        clock += ticks
        previous = end
    return output


def patrol(unit, tick):
    route = [point(p) for p in unit["route"]]
    if len(route) == 1: return route[0], unit["facing"]
    segments = 2 * (len(route) - 1)
    segment = (tick // 4) % segments
    from_index = segment if segment < len(route) - 1 else segments - segment
    to_index = from_index + 1 if segment < len(route) - 1 else from_index - 1
    a, b = route[from_index], route[to_index]
    fraction = tick % 4 / 4
    return (a[0] * (1 - fraction) + b[0] * fraction,
            a[1] * (1 - fraction) + b[1] * fraction), direction(a, b)


def check(level):
    assert len(level["map"]) == 9 and all(len(row) == 9 for row in level["map"]), level["id"]
    assert level["site"] and level["title"] and level["hint"] and level["briefing"]
    assert level["loot"] and floor(level, point(level["escape"]))
    for p in list(level["starts"].values()) + [i["at"] for key in ("loot", "cameras", "terminals") for i in level[key]]:
        assert floor(level, point(p)), (level["id"], p)
    starts = {role: point(start) for role, start in level["starts"].items()}
    scripts = {}
    for role, start in starts.items():
        actions = level["reference"]["actions"].get(role, [])
        scripts[role] = script(actions, start)
        for action, begin, end, a, b in scripts[role]:
            assert end > begin
            assert floor(level, b)
            if action["kind"] == "move": assert distance(a, b) == 1, (level["id"], action)
            if action["kind"] == "take":
                assert role == "thief" and any(i["id"] == action["target"] and point(i["at"]) == a for i in level["loot"])
            if action["kind"] == "hack":
                assert role == "hacker" and any(i["id"] == action["target"] and distance(point(i["at"]), a) <= 1 for i in level["terminals"])
            if action["kind"] == "distract": assert role == "decoy"
    all_actions = [(role, row) for role, rows in scripts.items() for row in rows]

    def location(role, tick):
        previous = starts[role]
        for action, begin, end, a, b in scripts[role]:
            if end <= tick: previous = b
            elif begin <= tick < end:
                f = (tick - begin) / (end - begin) if action["kind"] == "move" else 0
                return (a[0] * (1 - f) + b[0] * f, a[1] * (1 - f) + b[1] * f), previous
        return previous, previous

    for tick in range(41):
        actors = {role: location(role, tick) for role in starts}
        taken = {row[0]["target"] for role, row in all_actions if role == "thief" and row[0]["kind"] == "take" and row[2] <= tick}
        hacks = [row for role, row in all_actions if role == "hacker" and row[0]["kind"] == "hack" and row[2] <= tick]
        signals = [row for role, row in all_actions if role == "decoy" and row[0]["kind"] == "distract" and row[2] <= tick < row[2] + 12]
        security = []
        for unit in level["guards"]:
            active_signal = next((row for row in reversed(signals) if distance(patrol(unit, row[2])[0], row[4]) <= 6), None)
            if active_signal:
                position = patrol(unit, active_signal[2])[0]
                facing = direction(position, active_signal[4])
            else: position, facing = patrol(unit, tick)
            security.append((unit["id"], position, facing, unit["range"], 32))
        for cam in level["cameras"]:
            disabled = any(t["id"] == hack[0]["target"] and cam["id"] in t["disables"] and tick < hack[2] + t["durationTicks"]
                           for hack in hacks for t in level["terminals"])
            if not disabled:
                security.append((cam["id"], point(cam["at"]), cam["sweep"][(tick // 8) % len(cam["sweep"])], cam["range"], 24))
        for role in ("thief", "hacker"):
            if role not in actors: continue
            for name, origin, facing, reach, angle in security:
                if seeing(level, origin, facing, actors[role][0], reach, angle):
                    return False, f"{role} spotted by {name} at {tick / 4:.2f}s"
        if len(taken) == len(level["loot"]) and actors["thief"][1] == point(level["escape"]):
            return True, f"{tick / 4:.2f}s"
    return False, "timeout"


if __name__ == "__main__":
    levels = json.loads(LEVELS.read_text())
    assert len(set(item["id"] for item in levels)) == len(levels)
    failures = []
    for index, level in enumerate(levels, 1):
        success, result = check(level)
        print(f"{index:02} {level['title']}: {result}")
        if not success: failures.append(level["id"])
    print(f"{len(levels) - len(failures)}/{len(levels)} authored reference plans verified by Python check")
    if failures: raise SystemExit(f"Unverified levels: {', '.join(failures)}")
