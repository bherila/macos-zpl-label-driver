#!/usr/bin/env python3
"""Read-only: every acceptance criterion declares exactly one execution surface.

The prescribed A/C/I/H/R level says what a pass establishes. It does not say what
session is needed to obtain one, and that is the question an agent actually has:
criteria at level I can need hosted CI, a supervised GUI session, an installed
scheduler on a test Mac, or a named reference Mac holding a benchmark baseline.

docs/test-surfaces.json records that second answer, and it keeps two questions
apart that are easy to merge into one wrong number. A surface says WHERE a pass
can be obtained. runsPerPullRequest says whether an ORDINARY pull request -- the
one under review, with no extra apparatus -- reaches that surface. Two surfaces
may share a location and differ in reach, which is why repository inspection is
split into config and config-experiment: proving CI fails closed needs pull
requests built for that purpose, not the pull request being reviewed.

This checker keeps the map honest against docs/milestones.json: the same
criterion identifiers, no orphans either way, a surface whose declared level
matches the level the criterion actually prescribes, and a runsPerPullRequest
that is genuinely true or false rather than something Python happens to find
truthy. A surface implies a level, so changing one without the other is a
contradiction this refuses rather than reports.

It records where a criterion CAN be validated and nothing about whether it HAS
been. That is docs/ACCEPTANCE-EVIDENCE.json, and a surface here never counts as
evidence there.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MILESTONES = 'docs/milestones.json'
SURFACES = 'docs/test-surfaces.json'
LEVELS = {'A', 'C', 'I', 'H', 'R'}
UNREACHABLE_LEVELS = {'H', 'R'}
SUPPORTED_SCHEMA = 1
REQUIRED_SURFACE_KEYS = {'level', 'runsOn', 'runsPerPullRequest', 'establishes', 'doesNotEstablish'}


class Unevaluable(Exception):
    """The input could not be read or parsed, so no verdict is possible."""


def prescribed_levels(milestones):
    """Map each criterion identifier to the level docs/milestones.json prescribes.

    Identifiers are positional: the criteria list of milestone N yields M<N>-AC01
    upward, in order. The file stores no identifier of its own, so this derivation
    is the only definition there is.
    """
    levels = {}
    for milestone in milestones:
        number = milestone['n']
        for index, criterion in enumerate(milestone['criteria'], 1):
            level = criterion[1]
            if level not in LEVELS:
                raise Unevaluable(f'M{number}-AC{index:02d} prescribes unknown level {level!r}')
            levels[f'M{number}-AC{index:02d}'] = level
    return levels


def findings(levels, surfaces):
    """Every disagreement between the prescribed levels and the surface map."""
    found = []
    if surfaces.get('schemaVersion') != SUPPORTED_SCHEMA:
        raise Unevaluable(f'unsupported schemaVersion {surfaces.get("schemaVersion")!r}')

    definitions = surfaces.get('surfaces') or {}
    for name, definition in sorted(definitions.items()):
        missing = REQUIRED_SURFACE_KEYS - set(definition)
        if missing:
            found.append(f'surface {name!r} omits {", ".join(sorted(missing))}')
            continue
        if definition['level'] not in LEVELS:
            found.append(f'surface {name!r} declares unknown level {definition["level"]!r}')
        reach = definition['runsPerPullRequest']
        if not isinstance(reach, bool):
            # A JSON string "false" is truthy, so an unchecked flag would silently promote
            # every criterion on this surface into the reachable count -- the one number this
            # file exists to keep true. Refuse the definition, never Python truthiness.
            found.append(
                f'surface {name!r} declares runsPerPullRequest {reach!r}, which is not true or false')
        elif reach and definition['level'] in UNREACHABLE_LEVELS:
            # AGENTS.md: CI must never reach private printers, and publishing is separately
            # authorized. A level H or R surface an ordinary pull request reached would be one
            # of those things happening, so the claim is refused rather than counted.
            found.append(
                f'surface {name!r} is level {definition["level"]} but claims an ordinary pull request '
                f'reaches it; CI reaches neither a private printer nor the release gate')

    assigned = surfaces.get('criteria') or {}
    for identifier in sorted(set(levels) - set(assigned)):
        found.append(f'{identifier} has no declared execution surface')
    for identifier in sorted(set(assigned) - set(levels)):
        found.append(f'{identifier} is assigned a surface but is not a criterion in {MILESTONES}')

    for identifier in sorted(set(levels) & set(assigned)):
        name = assigned[identifier]
        definition = definitions.get(name)
        if definition is None:
            found.append(f'{identifier} names undefined surface {name!r}')
            continue
        declared = definition.get('level')
        if declared in LEVELS and declared != levels[identifier]:
            found.append(
                f'{identifier} prescribes level {levels[identifier]} but surface {name!r} is level {declared}')
    return found


def summarise(levels, surfaces):
    """Counts per surface, plus how many criteria an ordinary pull request reaches."""
    definitions = surfaces['surfaces']
    assigned = surfaces['criteria']
    counts = {name: 0 for name in definitions}
    for identifier in levels:
        counts[assigned[identifier]] = counts.get(assigned[identifier], 0) + 1
    reachable = sum(n for name, n in counts.items() if definitions[name]['runsPerPullRequest'])
    return counts, reachable


def load(path):
    try:
        return json.loads((ROOT / path).read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise Unevaluable(f'{path}: {error}') from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quiet', action='store_true', help='print findings only, not the summary')
    arguments = parser.parse_args()
    try:
        levels = prescribed_levels(load(MILESTONES))
        surfaces = load(SURFACES)
        found = findings(levels, surfaces)
    except Unevaluable as error:
        print(f'Cannot evaluate the execution-surface map: {error}', file=sys.stderr)
        return 2

    if found:
        for finding in found:
            print(f'  [gate] {finding}', file=sys.stderr)
        print(f'{len(found)} execution-surface finding(s); {SURFACES} and {MILESTONES} disagree.',
              file=sys.stderr)
        return 1

    if not arguments.quiet:
        counts, reachable = summarise(levels, surfaces)
        definitions = surfaces['surfaces']
        print(f'Execution surfaces agree with {MILESTONES} for all {len(levels)} criteria.')
        for name in sorted(counts, key=lambda k: (-counts[k], k)):
            marker = ('every ordinary pull request' if definitions[name]['runsPerPullRequest']
                      else 'a separate named session')
            print(f'  {name:<17} {counts[name]:>3}  level {definitions[name]["level"]}  {marker}')
        print(f'{reachable} of {len(levels)} criteria sit on a surface an ordinary pull request reaches; '
              f'{len(levels) - reachable} need a separate named session.')
        print('Reachable is not validated: a surface says where a pass could be obtained, never that one was.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
