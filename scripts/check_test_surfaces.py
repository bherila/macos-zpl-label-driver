#!/usr/bin/env python3
"""Read-only: every acceptance criterion declares exactly one execution surface.

The prescribed A/C/I/H/R level says what a pass establishes. It does not say what
session is needed to obtain one, and that is the question an agent actually has:
three criteria at level I can need three different sessions -- hosted CI, a
supervised GUI session, and an installed scheduler on a test Mac.

docs/test-surfaces.json records that second answer. This checker keeps it honest
against docs/milestones.json: the same criterion identifiers, no orphans either
way, and a surface whose declared level matches the level the criterion actually
prescribes. A surface implies a level, so changing one without the other is a
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
        elif definition['level'] not in LEVELS:
            found.append(f'surface {name!r} declares unknown level {definition["level"]!r}')

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
    """Counts per surface, plus how many criteria a pull request can reach at all."""
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
            marker = 'every pull request' if definitions[name]['runsPerPullRequest'] else 'a separate session'
            print(f'  {name:<13} {counts[name]:>3}  level {definitions[name]["level"]}  {marker}')
        print(f'{reachable} of {len(levels)} criteria sit on a surface a pull request can reach.')
        print('Reachable is not validated: a surface says where a pass could be obtained, never that one was.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
