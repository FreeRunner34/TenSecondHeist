"""Authored campaign source. Run this script to rebuild levels.json; no random generation."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "TenSecondHeist/Resources/levels.json"

OPEN = ["#########", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "#########"]
GALLERY = ["#########", "#...#...#", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "#...#...#", "#########"]
ARCHIVE = ["#########", "#.......#", "#..#.#..#", "#.......#", "#.......#", "#.......#", "#..#.#..#", "#.......#", "#########"]
PENTHOUSE = ["#########", "#.......#", "#.##.##.#", "#.......#", "#.......#", "#.......#", "#.##.##.#", "#.......#", "#########"]
VAULT = ["#########", "#.......#", "#.#...#.#", "#.......#", "#.......#", "#.......#", "#.#...#.#", "#.......#", "#########"]


def tile(x, y): return {"x": x, "y": y}
def fixture(name, x, y): return {"id": name, "at": tile(x, y)}
def guard(name, route, facing="south", range=3.2):
    return {"id": name, "route": [tile(*p) for p in route], "facing": facing, "range": range}
def camera(name, x, y, sweep=("south",), range=3.6, terminal=None):
    return {"id": name, "at": tile(x, y), "sweep": list(sweep), "range": range, "terminal": terminal}
def terminal(name, x, y, cameras, duration=24):
    return {"id": name, "at": tile(x, y), "disables": list(cameras), "durationTicks": duration}


def actions(start, instructions, loot, terminals):
    x, y = start
    result = []
    for instruction in instructions.split():
        if instruction in ("R", "L", "U", "D"):
            dx, dy = {"R": (1, 0), "L": (-1, 0), "U": (0, -1), "D": (0, 1)}[instruction]
            x += dx; y += dy
            result.append({"kind": "move", "at": tile(x, y)})
        elif instruction.startswith("w"):
            result.append({"kind": "wait", "ticks": int(instruction[1:])})
        elif instruction == "t":
            matches = [item for item in loot if item["at"] == tile(x, y)]
            assert matches, f"Take action has no valuable at {(x, y)}"
            result.append({"kind": "take", "target": matches[0]["id"]})
        elif instruction == "h":
            matches = [item for item in terminals if item["at"] == tile(x, y)]
            assert matches, f"Hack action has no terminal at {(x, y)}"
            result.append({"kind": "hack", "target": matches[0]["id"]})
        elif instruction == "d": result.append({"kind": "distract"})
        else: raise ValueError(instruction)
    return result


LEVELS = []


def author(title, site, difficulty, briefing, map, starts, exit, loot, hint,
           thief, hacker=None, decoy=None, guards=(), cameras=(), terminals=(), action_target=16):
    n = len(LEVELS) + 1
    valuables = [fixture(f"Loot {n}-{i+1}", *position) for i, position in enumerate(loot)]
    starts = {key: tile(*value) for key, value in starts.items()}
    reference = {"thief": actions((starts["thief"]["x"], starts["thief"]["y"]), thief, valuables, terminals)}
    if hacker is not None:
        reference["hacker"] = actions((starts["hacker"]["x"], starts["hacker"]["y"]), hacker, valuables, terminals)
    if decoy is not None:
        reference["decoy"] = actions((starts["decoy"]["x"], starts["decoy"]["y"]), decoy, valuables, terminals)
    LEVELS.append({
        "id": f"heist-{n:02}", "title": title, "site": site, "difficulty": difficulty,
        "briefing": briefing, "map": map, "starts": starts, "escape": tile(*exit),
        "loot": valuables, "guards": list(guards), "cameras": list(cameras),
        "terminals": list(terminals), "hint": hint, "actionTarget": action_target,
        "reference": {"actions": reference}
    })


author("The Invitation", "The Gilt Gallery", 1,
       "One canvas. One exit. Learn the rhythm before the building wakes up.",
       GALLERY, {"thief": (1, 5)}, (7, 5), [(4, 5)],
       "Draw a route to the canvas, take it, then reach the teal exit.",
       "R R R t R R R", action_target=7)
author("The Night Watch", "The Gilt Gallery", 1,
       "The guard walks the same short beat every time. Read the footsteps.",
       GALLERY, {"thief": (1, 5)}, (7, 5), [(5, 5)],
       "The guard looks north while you cross the center line.",
       "R R R R t R R", guards=[guard("Guard A", [(4, 4), (4, 5)])], action_target=8)
author("A Moment in the Dark", "The Gilt Gallery", 2,
       "Camera B sweeps away for a moment. Waiting is part of the plan.",
       GALLERY, {"thief": (1, 5)}, (7, 5), [(6, 5)],
       "Wait one second, then cross the camera's column while it faces east.",
       "w4 R R R R R t R", cameras=[camera("Camera B", 4, 3, ("south", "east", "north", "east"))], action_target=8)
author("Borrowed Darkness", "The Gilt Gallery", 2,
       "The hacker has a window. The thief needs to use it.",
       GALLERY, {"thief": (1, 5), "hacker": (1, 2)}, (7, 5), [(6, 5)],
       "Hack the terminal and have the thief start moving once the camera goes dark.",
       "w6 R R R R R t R", hacker="R h", cameras=[camera("Camera C", 4, 3, terminal="Panel C")],
       terminals=[terminal("Panel C", 2, 2, ("Camera C",))], action_target=10)
author("The Whole Crew", "The Gilt Gallery", 3,
       "Three crew members. One ten-second window.",
       GALLERY, {"thief": (1, 5), "hacker": (1, 2), "decoy": (7, 2)}, (7, 5), [(6, 5)],
       "Hack first. Time the decoy's signal to face Guard D away from the thief.",
       "w6 R R R R R t R", hacker="R h", decoy="L w6 d",
       guards=[guard("Guard D", [(5, 3)])], cameras=[camera("Camera D", 4, 3, terminal="Panel D")],
       terminals=[terminal("Panel D", 2, 2, ("Camera D",))], action_target=13)

author("Double Exposure", "The Gilt Gallery", 3,
       "The collector left two originals out. Grab both before the lens returns.",
       GALLERY, {"thief": (1, 5), "hacker": (1, 2)}, (7, 5), [(3, 5), (6, 5)],
       "A single hack gives enough time for both pickups. Mark each canvas separately.",
       "w6 R R t R R R t R", hacker="R h",
       cameras=[camera("Camera E", 4, 3, terminal="Panel E")],
       terminals=[terminal("Panel E", 2, 2, ("Camera E",))], action_target=12)
author("The Quiet Door", "The Gilt Gallery", 3,
       "A service door cuts through the night watch's lane.",
       [*GALLERY[:5], "#...+...#", *GALLERY[6:]], {"thief": (1, 5)}, (7, 5), [(5, 5)],
       "Doors are walkable. The guard's patrol repeats every two seconds.",
       "R R R R t R R", guards=[guard("Guard F", [(4, 4), (4, 5)])], action_target=8)
author("Curtain Call", "The Gilt Gallery", 3,
       "Enter from the east. The lens still sweeps on its own clock.",
       GALLERY, {"thief": (7, 5)}, (1, 5), [(2, 5)],
       "Wait for the east-facing sweep, then move west across its column.",
       "w4 L L L L L t L",
       cameras=[camera("Camera G", 4, 3, ("south", "east", "north", "east"))], action_target=8)
author("Blind Spot", "The Gilt Gallery", 4,
       "Two lenses share one breaker. Give them both a reason to blink.",
       GALLERY, {"thief": (1, 5), "hacker": (1, 2)}, (7, 5), [(6, 5)],
       "Panel H shuts down Camera H and Camera I at the same moment.",
       "w6 R R R R R t R", hacker="R h",
       cameras=[camera("Camera H", 4, 3, terminal="Panel H"), camera("Camera I", 5, 3, terminal="Panel H")],
       terminals=[terminal("Panel H", 2, 2, ("Camera H", "Camera I"))], action_target=10)
author("Understudies", "The Gilt Gallery", 4,
       "The guard and camera each have a predictable blind beat.",
       GALLERY, {"thief": (1, 5), "decoy": (7, 2)}, (7, 5), [(6, 5)],
       "Let Camera J turn east. Signal from the decoy to turn the guard north.",
       "w6 R R R R R t R", decoy="L w6 d",
       guards=[guard("Guard J", [(5, 3)])],
       cameras=[camera("Camera J", 4, 3, ("south", "east", "north", "east"))], action_target=11)
author("Clockwork", "The Gilt Gallery", 4,
       "A patrolling guard and a sweeping lens cross the same room.",
       GALLERY, {"thief": (1, 5), "decoy": (7, 2)}, (7, 5), [(6, 5)],
       "The guard will follow a signal even while his regular patrol continues on the timeline.",
       "w6 R R R R R t R", decoy="L w6 d",
       guards=[guard("Guard K", [(4, 4), (4, 5)])],
       cameras=[camera("Camera K", 4, 3, ("south", "east", "north", "east"))], action_target=11)
author("Last Look", "The Gilt Gallery", 5,
       "One last room: two canvases, two lenses, and a guard who knows the exits.",
       GALLERY, {"thief": (1, 5), "hacker": (1, 2), "decoy": (7, 2)}, (7, 5), [(3, 5), (6, 5)],
       "The first canvas delays the thief. Signal late enough to cover the second pickup.",
       "w6 R R t R R R t R", hacker="R h", decoy="L w6 d",
       guards=[guard("Guard L", [(5, 3)])],
       cameras=[camera("Camera L", 4, 3, terminal="Panel L"), camera("Camera M", 5, 3, terminal="Panel L")],
       terminals=[terminal("Panel L", 2, 2, ("Camera L", "Camera M"))], action_target=15)

author("Reverse Entry", "The Blue Archive", 2,
       "The stacks hide an east entrance. The archive guard has a short route.",
       ARCHIVE, {"thief": (7, 5)}, (1, 5), [(2, 5)],
       "Cross the patrol lane when the guard turns back toward the shelves.",
       "L L L L L t L", guards=[guard("Archivist A", [(4, 4), (4, 5)])], action_target=7)
author("Stacks After Hours", "The Blue Archive", 2,
       "A cataloging camera sweeps the central aisle on a regular beat.",
       ARCHIVE, {"thief": (7, 5)}, (1, 5), [(2, 5)],
       "Cross the center after the camera turns to the east.",
       "w4 L L L L L t L",
       cameras=[camera("Archive Camera B", 4, 3, ("south", "east", "north", "east"))], action_target=8)
author("The Switchboard", "The Blue Archive", 3,
       "One breaker covers the east aisle. Give the thief a clean start.",
       ARCHIVE, {"thief": (7, 5), "hacker": (7, 2)}, (1, 5), [(2, 5)],
       "The hacker can reach the panel in half a second. The blackout starts after hacking completes.",
       "w6 L L L L L t L", hacker="L h",
       cameras=[camera("Archive Camera C", 4, 3, terminal="Archive Panel C")],
       terminals=[terminal("Archive Panel C", 6, 2, ("Archive Camera C",))], action_target=10)
author("Catalog Distraction", "The Blue Archive", 3,
       "An attentive archivist has a clear view of the borrowed folio.",
       ARCHIVE, {"thief": (7, 5), "decoy": (1, 2)}, (1, 5), [(2, 5)],
       "Signal from the west so the archivist faces away from the floor aisle.",
       "w6 L L L L L t L", decoy="R w6 d",
       guards=[guard("Archivist D", [(3, 3)])], action_target=11)
author("Two Ledgers", "The Blue Archive", 3,
       "The records were split. Both ledgers must leave together.",
       ARCHIVE, {"thief": (7, 5), "hacker": (7, 2)}, (1, 5), [(5, 5), (2, 5)],
       "Take each ledger as you pass. A single breaker shuts the camera down long enough.",
       "w6 L L t L L L t L", hacker="L h",
       cameras=[camera("Archive Camera E", 4, 3, terminal="Archive Panel E")],
       terminals=[terminal("Archive Panel E", 6, 2, ("Archive Camera E",))], action_target=12)
author("Telltale Beam", "The Blue Archive", 3,
       "The upper aisle is exposed to a lens pointing up from the stacks.",
       ARCHIVE, {"thief": (1, 3)}, (7, 3), [(6, 3)],
       "The upward sweep lasts two seconds. Cross its column after it turns right.",
       "w4 R R R R R t R",
       cameras=[camera("Archive Camera F", 4, 5, ("north", "east", "south", "east"))], action_target=8)
author("Subfloor Wiring", "The Blue Archive", 4,
       "The hacker slips below the shelves while the thief takes the upper aisle.",
       ARCHIVE, {"thief": (1, 3), "hacker": (1, 6)}, (7, 3), [(6, 3)],
       "The terminal below disables the upward-facing camera.",
       "w6 R R R R R t R", hacker="R h",
       cameras=[camera("Archive Camera G", 4, 5, ("north",), terminal="Archive Panel G")],
       terminals=[terminal("Archive Panel G", 2, 6, ("Archive Camera G",))], action_target=10)
author("Cover Story", "The Blue Archive", 4,
       "The security guard watches the upper aisle from the records desk.",
       ARCHIVE, {"thief": (1, 3), "decoy": (7, 6)}, (7, 3), [(6, 3)],
       "Signal from below the desk. The guard looks down for three seconds.",
       "w6 R R R R R t R", decoy="L w6 d",
       guards=[guard("Archivist H", [(5, 5)], facing="north")], action_target=11)
author("Copy Room", "The Blue Archive", 4,
       "Two red lenses cover the return route; one breaker feeds both.",
       ARCHIVE, {"thief": (7, 5), "hacker": (7, 2)}, (1, 5), [(2, 5)],
       "Both cameras go dark together. Watch the disabled indicators on the timeline.",
       "w6 L L L L L t L", hacker="L h",
       cameras=[camera("Archive Camera I", 4, 3, terminal="Archive Panel I"),
                camera("Archive Camera J", 3, 3, terminal="Archive Panel I")],
       terminals=[terminal("Archive Panel I", 6, 2, ("Archive Camera I", "Archive Camera J"))], action_target=10)
author("Loose Index", "The Blue Archive", 5,
       "A beam and a watchful archivist share the upper aisle.",
       ARCHIVE, {"thief": (1, 3), "hacker": (1, 6), "decoy": (7, 6)}, (7, 3), [(6, 3)],
       "The hacker handles the beam. The decoy turns the archivist toward the lower floor.",
       "w6 R R R R R t R", hacker="R h", decoy="L w6 d",
       guards=[guard("Archivist K", [(5, 5)], facing="north")],
       cameras=[camera("Archive Camera K", 4, 5, ("north",), terminal="Archive Panel K")],
       terminals=[terminal("Archive Panel K", 2, 6, ("Archive Camera K",))], action_target=13)
author("Redacted Files", "The Blue Archive", 5,
       "A sweeping camera and a patrolling guard complicate the return aisle.",
       ARCHIVE, {"thief": (7, 5), "decoy": (1, 2)}, (1, 5), [(2, 5)],
       "The camera turns east while the archivist follows the west-side distraction.",
       "w6 L L L L L t L", decoy="R w6 d",
       guards=[guard("Archivist L", [(4, 4), (4, 5)])],
       cameras=[camera("Archive Camera L", 4, 3, ("south", "east", "north", "east"))], action_target=11)
author("Midnight Inventory", "The Blue Archive", 5,
       "The stolen index has two halves, and all three crew members have a job.",
       ARCHIVE, {"thief": (1, 3), "hacker": (1, 6), "decoy": (7, 6)}, (7, 3), [(3, 3), (6, 3)],
       "Collect the early file, then let the decoy cover the later crossing.",
       "w6 R R t R R R t R", hacker="R h", decoy="L w6 d",
       guards=[guard("Archivist M", [(5, 5)], facing="north")],
       cameras=[camera("Archive Camera M", 4, 5, ("north",), terminal="Archive Panel M")],
       terminals=[terminal("Archive Panel M", 2, 6, ("Archive Camera M",))], action_target=15)

author("Rooftop Valet", "The Amber Penthouse", 2,
       "Slip past the empty valet desk and leave with two sparkling pieces.",
       PENTHOUSE, {"thief": (1, 5)}, (7, 5), [(3, 5), (6, 5)],
       "Both jewels require a TAKE action. The getaway door is at the far right.",
       "R R t R R R t R", action_target=8)
author("Glass Elevator", "The Amber Penthouse", 3,
       "A lens above the elevator divides the hall in two.",
       PENTHOUSE, {"thief": (1, 5)}, (7, 5), [(6, 5)],
       "The camera turns toward the east side after two seconds.",
       "w4 R R R R R t R", cameras=[camera("Lift Camera", 4, 3, ("south", "east", "north", "east"))], action_target=8)
author("Service Console", "The Amber Penthouse", 3,
       "The gallery feed runs through a discreet service console.",
       PENTHOUSE, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(6, 5)],
       "Have the hacker take one step to the console, then the thief can cross.",
       "w6 R R R R R t R", hacker="R h",
       cameras=[camera("Gallery Feed", 4, 3, terminal="Service Console")],
       terminals=[terminal("Service Console", 2, 4, ("Gallery Feed",))], action_target=10)
author("The Guest List", "The Amber Penthouse", 3,
       "The doorman remembers faces. Give him a different one.",
       PENTHOUSE, {"thief": (1, 5), "decoy": (7, 2)}, (7, 5), [(6, 5)],
       "The decoy can signal from the upper right and turn the doorman east.",
       "w6 R R R R R t R", decoy="D w6 d",
       guards=[guard("Doorman", [(5, 3)])], action_target=11)
author("Bedroom Detour", "The Amber Penthouse", 4,
       "One jewel is off the main route; the other sits across the camera's sightline.",
       PENTHOUSE, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(3, 4), (6, 5)],
       "Step up for the first jewel, return to the hall, then take the second.",
       "w6 R R U t D R R R t R", hacker="R h",
       cameras=[camera("Suite Camera", 4, 3, terminal="Suite Panel")],
       terminals=[terminal("Suite Panel", 2, 4, ("Suite Camera",))], action_target=14)
author("Silent Balcony", "The Amber Penthouse", 3,
       "The upstairs hall is watched from below by a rotating lens.",
       PENTHOUSE, {"thief": (1, 3)}, (7, 3), [(6, 3)],
       "Hold for one second, then cross while the lens points east.",
       "w4 R R R R R t R",
       cameras=[camera("Balcony Camera", 4, 5, ("north", "east", "south", "east"))], action_target=8)
author("Indoor Pool", "The Amber Penthouse", 4,
       "A guard watches the upstairs hall from the poolside.",
       PENTHOUSE, {"thief": (1, 3), "decoy": (7, 6)}, (7, 3), [(6, 3)],
       "A signal beside the pool turns the guard away from the upper walkway.",
       "w6 R R R R R t R", decoy="U w6 d",
       guards=[guard("Pool Guard", [(5, 5)], facing="north")], action_target=11)
author("House Network", "The Amber Penthouse", 4,
       "One house panel controls two watchful cameras.",
       PENTHOUSE, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(6, 5)],
       "Both feeds share the same shutdown window. Start your thief after the hack.",
       "w6 R R R R R t R", hacker="R h",
       cameras=[camera("House Camera A", 4, 3, terminal="House Panel"),
                camera("House Camera B", 5, 3, terminal="House Panel")],
       terminals=[terminal("House Panel", 2, 4, ("House Camera A", "House Camera B"))], action_target=10)
author("Dinner Bell", "The Amber Penthouse", 5,
       "Two pieces are out for display. Security expects the guests to stay put.",
       PENTHOUSE, {"thief": (1, 5), "decoy": (7, 2)}, (7, 5), [(3, 5), (6, 5)],
       "A later signal keeps the guard occupied during the second pickup.",
       "w6 R R t R R R t R", decoy="D w8 d",
       guards=[guard("Dining Guard", [(5, 3)])],
       cameras=[camera("Dining Camera", 4, 3, ("south", "east", "north", "east"))], action_target=13)
author("Private Collection", "The Amber Penthouse", 5,
       "Guard, camera, and crew converge on the upper hallway.",
       PENTHOUSE, {"thief": (1, 3), "hacker": (1, 4), "decoy": (7, 6)}, (7, 3), [(6, 3)],
       "The hack blocks the lens. The poolside signal redirects the guard.",
       "w6 R R R R R t R", hacker="R h", decoy="U w6 d",
       guards=[guard("Collection Guard", [(5, 5)], facing="north")],
       cameras=[camera("Collection Camera", 4, 5, ("north",), terminal="Collection Panel")],
       terminals=[terminal("Collection Panel", 2, 4, ("Collection Camera",))], action_target=13)
author("The Switch", "The Amber Penthouse", 5,
       "Enter from the service lift while the household gathers on the other side.",
       PENTHOUSE, {"thief": (7, 5), "hacker": (7, 4), "decoy": (1, 2)}, (1, 5), [(2, 5)],
       "The west-side decoy faces the guard away from the reverse exit route.",
       "w6 L L L L L t L", hacker="L h", decoy="D w6 d",
       guards=[guard("West Guard", [(3, 3)])],
       cameras=[camera("Lift Feed", 4, 3, terminal="Lift Panel")],
       terminals=[terminal("Lift Panel", 6, 4, ("Lift Feed",))], action_target=13)
author("Penthouse Exit", "The Amber Penthouse", 5,
       "A double pickup and a room detour put every second under pressure.",
       PENTHOUSE, {"thief": (1, 5), "hacker": (1, 4), "decoy": (7, 2)}, (7, 5), [(3, 4), (6, 5)],
       "Time the decoy later; the detour delays the thief's crossing.",
       "w6 R R U t D R R R t R", hacker="R h", decoy="D w12 d",
       guards=[guard("Final Guard", [(5, 3)])],
       cameras=[camera("Final Feed A", 4, 3, terminal="Final Panel"),
                camera("Final Feed B", 5, 3, terminal="Final Panel")],
       terminals=[terminal("Final Panel", 2, 4, ("Final Feed A", "Final Feed B"))], action_target=17)

author("Intake Bay", "The Meridian Vault", 3,
       "The freight entrance offers a direct lane, with one predictable patrol.",
       VAULT, {"thief": (7, 5)}, (1, 5), [(2, 5)],
       "The guard turns north as you cross the center of the intake lane.",
       "L L L L L t L", guards=[guard("Vault Guard A", [(4, 4), (4, 5)])], action_target=7)
author("Pressure Line", "The Meridian Vault", 3,
       "A vault camera surveys the access corridor, then checks its side wall.",
       VAULT, {"thief": (1, 5)}, (7, 5), [(6, 5)],
       "Wait for the eastward camera sweep before crossing its vertical sightline.",
       "w4 R R R R R t R",
       cameras=[camera("Pressure Camera", 4, 3, ("south", "east", "north", "east"))], action_target=8)
author("Control Room", "The Meridian Vault", 4,
       "The vault cameras answer to a guarded control terminal below the hallway.",
       VAULT, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(6, 5)],
       "Hack at the near panel, then follow the camera's inactive indicator.",
       "w6 R R R R R t R", hacker="R h",
       cameras=[camera("Control Camera", 4, 3, terminal="Control Panel")],
       terminals=[terminal("Control Panel", 2, 4, ("Control Camera",), duration=22)], action_target=10)
author("False Delivery", "The Meridian Vault", 4,
       "A guard expects a courier. The decoy can oblige.",
       VAULT, {"thief": (1, 5), "decoy": (7, 2)}, (7, 5), [(6, 5)],
       "The signal comes from above and right of the guard, redirecting his attention.",
       "w6 R R R R R t R", decoy="D w6 d",
       guards=[guard("Courier Guard", [(5, 3)])], action_target=11)
author("Redundancy", "The Meridian Vault", 4,
       "Two cameras protect the strong room, both wired to one accessible panel.",
       VAULT, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(6, 5)],
       "Watch both disabled indicators after the hacker finishes.",
       "w6 R R R R R t R", hacker="R h",
       cameras=[camera("Vault Camera A", 4, 3, terminal="Redundant Panel"),
                camera("Vault Camera B", 5, 3, terminal="Redundant Panel")],
       terminals=[terminal("Redundant Panel", 2, 4, ("Vault Camera A", "Vault Camera B"), duration=22)], action_target=10)
author("Side Drawer", "The Meridian Vault", 4,
       "One deposit is above the hall; the other is at the end of it.",
       VAULT, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(3, 4), (6, 5)],
       "The upper drawer costs a detour. Keep the camera off for the later crossing.",
       "w6 R R U t D R R R t R", hacker="R h",
       cameras=[camera("Drawer Camera", 4, 3, terminal="Drawer Panel")],
       terminals=[terminal("Drawer Panel", 2, 4, ("Drawer Camera",), duration=24)], action_target=14)
author("Motion Study", "The Meridian Vault", 4,
       "The upper corridor is watched from below by a guard and rotating camera.",
       VAULT, {"thief": (1, 3), "decoy": (7, 6)}, (7, 3), [(6, 3)],
       "The lens turns east as the decoy draws the guard toward the south.",
       "w6 R R R R R t R", decoy="U w6 d",
       guards=[guard("Upper Guard", [(5, 5)], facing="north")],
       cameras=[camera("Upper Camera", 4, 5, ("north", "east", "south", "east"))], action_target=11)
author("Access Chain", "The Meridian Vault", 5,
       "A single shutdown window has to cover two linked lenses and a timed pickup.",
       VAULT, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(3, 5), (6, 5)],
       "The camera stays dark long enough for both valuables when the thief starts after the hack.",
       "w6 R R t R R R t R", hacker="R h",
       cameras=[camera("Chain Camera A", 4, 3, terminal="Chain Panel"),
                camera("Chain Camera B", 5, 3, terminal="Chain Panel")],
       terminals=[terminal("Chain Panel", 2, 4, ("Chain Camera A", "Chain Camera B"), duration=22)], action_target=12)
author("Second Window", "The Meridian Vault", 5,
       "Enter from the opposite hall. The crew's jobs stay the same, but the angle changes.",
       VAULT, {"thief": (7, 5), "hacker": (7, 4), "decoy": (1, 2)}, (1, 5), [(2, 5)],
       "The hacker uses the east console while the west decoy turns the guard away.",
       "w6 L L L L L t L", hacker="L h", decoy="D w6 d",
       guards=[guard("Reverse Guard", [(3, 3)])],
       cameras=[camera("Reverse Camera", 4, 3, terminal="Reverse Panel")],
       terminals=[terminal("Reverse Panel", 6, 4, ("Reverse Camera",), duration=22)], action_target=13)
author("Long Way Round", "The Meridian Vault", 5,
       "Two deposits sit on different rows. Security meets in the middle.",
       VAULT, {"thief": (1, 5), "hacker": (1, 4), "decoy": (7, 2)}, (7, 5), [(3, 4), (6, 5)],
       "The first drawer takes time. Delay the decoy signal to cover the second crossing.",
       "w6 R R U t D R R R t R", hacker="R h", decoy="D w12 d",
       guards=[guard("Middle Guard", [(5, 3)])],
       cameras=[camera("Middle Camera", 4, 3, terminal="Middle Panel")],
       terminals=[terminal("Middle Panel", 2, 4, ("Middle Camera",), duration=26)], action_target=17)
author("Last Safe", "The Meridian Vault", 5,
       "Three valuables require a route through both rows of the strong room.",
       VAULT, {"thief": (1, 5), "hacker": (1, 4)}, (7, 5), [(3, 4), (5, 5), (6, 4)],
       "Plan the upper drawer, lower deposit, and final upper safe in that order.",
       "w6 R R U t D R R t U R t D R", hacker="R h",
       cameras=[camera("Safe Camera A", 4, 3, terminal="Safe Panel"),
                camera("Safe Camera B", 5, 3, terminal="Safe Panel")],
       terminals=[terminal("Safe Panel", 2, 4, ("Safe Camera A", "Safe Camera B"), duration=32)], action_target=17)
author("Zero Hour", "The Meridian Vault", 5,
       "The vault finale: three pickups, two cameras, one redirected guard, and one exit.",
       VAULT, {"thief": (1, 5), "hacker": (1, 6), "decoy": (1, 2)}, (7, 5), [(3, 4), (5, 5), (6, 4)],
       "Signal from the west shortly before the middle pickup; the guard must look away from the final safe.",
       "w6 R R U t D R R t U R t D R", hacker="h", decoy="D w14 d",
       guards=[guard("Vault Captain", [(5, 4)])],
       cameras=[camera("Final Camera A", 4, 3, terminal="Final Vault Panel"),
                camera("Final Camera B", 5, 3, terminal="Final Vault Panel")],
       terminals=[terminal("Final Vault Panel", 1, 6, ("Final Camera A", "Final Camera B"), duration=32)],
       action_target=20)


if __name__ == "__main__":
    OUT.write_text(json.dumps(LEVELS, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {len(LEVELS)} authored levels to {OUT.relative_to(ROOT)}")
