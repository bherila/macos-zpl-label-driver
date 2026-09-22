#!/usr/bin/env python3
"""Read-only: every acceptance criterion declares exactly one execution surface.

The prescribed A/C/I/H/R level says what a pass establishes. It does not say what
session is needed to obtain one, and that is the question an agent actually has:
criteria at level I can need hosted CI, a supervised GUI session, an installed
scheduler on a test Mac, or a named reference Mac holding a benchmark baseline.

docs/test-surfaces.json records that second answer, and it keeps two questions
apart that are easy to merge into one wrong number. A surface says WHERE a pass
can be obtained. `reach` says which pull requests get there: every ordinary one,
only the ones whose changed paths select the surface, or none, because the pass
needs apparatus the pull request under review does not have. Two surfaces may
share a location and differ in reach, which is why repository inspection is split
into config and config-experiment: proving CI fails closed needs pull requests
built for that purpose, not the pull request being reviewed. The level A rows
are split the same way and for the same reason, by which job actually runs them:
the always-running preflight job runs the Python checkers and scripts/tests,
while the Swift suite and the accelerator checks are reached only through
scripts/ci-swift.sh in the gated macOS job.

This checker keeps the map honest against docs/milestones.json: the same
criterion identifiers, no orphans either way, a surface whose declared level
matches the level the criterion actually prescribes, and a `reach` drawn from a
closed set rather than something Python happens to find truthy. A surface implies
a level, so changing one without the other is a contradiction this refuses rather
than reports.

It does NOT constrain reach by level. A level says what a pass establishes, not
whether a pull request may obtain one, and a constraint of that shape -- no level
H or R surface may be reached per pull request -- was the same conflation of the
two questions this file exists to separate. The honest basis for such a rule is a
declared effect, such as writing to a device or publishing an artifact, and this
map declares no effects.

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
REACH_EVERY = 'every-pull-request'
REACH_SELECTED = 'selected-pull-requests'
REACH_SEPARATE = 'separate-session'
REACH_VALUES = (REACH_EVERY, REACH_SELECTED, REACH_SEPARATE)
REQUIRED_SURFACE_KEYS = {'level', 'runsOn', 'reach', 'establishes', 'doesNotEstablish'}


class Unevaluable(Exception):
    """The input could not be read or parsed, so no verdict is possible."""


def prescribed_levels(milestones):
    """Map each criterion identifier to the level docs/milestones.json prescribes.

    Identifiers are positional: the criteria list of milestone N yields M<N>-AC01
    upward, in order. The file stores no identifier of its own, so this derivation
    is the only definition there is.
    """
    if not isinstance(milestones, list):
        raise Unevaluable(f'{MILESTONES} is {type(milestones).__name__}, not a JSON array')
    levels = {}
    for position, milestone in enumerate(milestones, 1):
        if not isinstance(milestone, dict):
            raise Unevaluable(
                f'milestone {position} is {type(milestone).__name__}, not a JSON object')
        number = milestone.get('n')
        if not isinstance(number, int) or isinstance(number, bool):
            raise Unevaluable(f'milestone {position} declares n {number!r}, which is not an integer')
        criteria = milestone.get('criteria')
        if not isinstance(criteria, list):
            raise Unevaluable(
                f'M{number} declares criteria as {type(criteria).__name__}, not a JSON array')
        for index, criterion in enumerate(criteria, 1):
            identifier = f'M{number}-AC{index:02d}'
            if not isinstance(criterion, list) or len(criterion) < 2:
                raise Unevaluable(f'{identifier} is not a criterion of at least title and level')
            level = criterion[1]
            # `level not in LEVELS` hashes its left operand, so an unhashable level raised
            # TypeError straight out of main() rather than refusing the document.
            if not isinstance(level, str):
                raise Unevaluable(
                    f'{identifier} prescribes level {level!r}, which is not a string')
            if level not in LEVELS:
                raise Unevaluable(f'{identifier} prescribes unknown level {level!r}')
            levels[identifier] = level
    return levels


def _object(document, key):
    """The value at `key`, which must be present and be a JSON object.

    The raw value is judged BEFORE any defaulting. `document.get(key) or {}`
    substituted an empty object for null, [] and "" -- every falsey malformed
    edit -- so `"surfaces": null` reached the comparison as an empty map and was
    reported as ninety criteria with no declared surface: exit 1, the code
    meaning the map and the milestones disagree, for a file that declared
    nothing at all. A missing key and a null key are both refusals here, and
    they say which one happened; an empty object is a real, evaluable document
    and stays a finding rather than a refusal.
    """
    if key not in document:
        raise Unevaluable(f'the document omits "{key}"')
    value = document[key]
    if not isinstance(value, dict):
        raise Unevaluable(f'"{key}" is {type(value).__name__}, not a JSON object')
    return value


def _shape(surfaces):
    """Refuse a document whose shape makes a verdict impossible, before reading any key.

    A surface that is null, a string or a list has no keys to read. Reading them
    anyway raised TypeError out of main(), which catches only Unevaluable, so a
    malformed file exited 1 -- the code meaning the map and the milestones
    disagree -- with a traceback, instead of 2, the code meaning no verdict is
    possible.
    """
    if not isinstance(surfaces, dict):
        raise Unevaluable(f'the document is {type(surfaces).__name__}, not a JSON object')
    version = surfaces.get('schemaVersion')
    # `!=` alone accepted anything Python calls equal to 1. `True == 1` and `1.0 == 1` are
    # both true, so `"schemaVersion": true` declared no schema version at all yet produced
    # no finding and exit 0. The declared version is an integer literal, so the type is
    # judged before the value. The same hole was already closed for `n` in
    # prescribed_levels(); this was the other side of it, left on a bare `!=`.
    if type(version) is not int or version != SUPPORTED_SCHEMA:
        raise Unevaluable(f'unsupported schemaVersion {version!r}')
    definitions = _object(surfaces, 'surfaces')
    assigned = _object(surfaces, 'criteria')
    for name, definition in sorted(definitions.items()):
        if not isinstance(definition, dict):
            raise Unevaluable(
                f'surface {name!r} is {type(definition).__name__}, not a JSON object')
    return definitions, assigned


def findings(levels, surfaces):
    """Every disagreement between the prescribed levels and the surface map."""
    found = []
    definitions, assigned = _shape(surfaces)

    for name, definition in sorted(definitions.items()):
        missing = REQUIRED_SURFACE_KEYS - set(definition)
        if missing:
            found.append(f'surface {name!r} omits {", ".join(sorted(missing))}')
            continue
        # Every required field is prose or a keyword, so every one of them is a non-empty
        # string. Checking the whole set rather than the field a reviewer happened to name
        # is the point: `level` reached `in LEVELS`, which hashes it, so `"level": []`
        # raised TypeError out of main(); `reach` is used as a dictionary key in
        # summarise(); and the rest are published. One sweep covers the class.
        mistyped = [key for key in sorted(REQUIRED_SURFACE_KEYS)
                    if not isinstance(definition[key], str) or not definition[key].strip()]
        if mistyped:
            found.append(f'surface {name!r} declares {", ".join(mistyped)} as something other '
                         f'than a non-empty string')
            continue
        if definition['level'] not in LEVELS:
            found.append(f'surface {name!r} declares unknown level {definition["level"]!r}')
        reach = definition['reach']
        condition = definition.get('reachedWhen')
        if reach not in REACH_VALUES:
            # This field decides the reachable count, the one number the file exists to keep
            # true. A JSON true, 1 or "yes" is truthy in Python, so the value is matched against
            # a closed set and never against Python truthiness.
            found.append(f'surface {name!r} declares reach {reach!r}, which is not one of '
                         + ', '.join(REACH_VALUES))
        elif reach == REACH_SELECTED and not (isinstance(condition, str) and condition.strip()):
            found.append(f'surface {name!r} is reached by selected pull requests but its '
                         f'reachedWhen names no condition')
        elif reach != REACH_SELECTED and condition is not None:
            found.append(f'surface {name!r} declares reach {reach} yet names the reachedWhen '
                         f'condition {condition!r}')

    for identifier in sorted(set(levels) - set(assigned)):
        found.append(f'{identifier} has no declared execution surface')
    for identifier in sorted(set(assigned) - set(levels)):
        found.append(f'{identifier} is assigned a surface but is not a criterion in {MILESTONES}')

    for identifier in sorted(set(levels) & set(assigned)):
        name = assigned[identifier]
        if not isinstance(name, str):
            found.append(f'{identifier} names {name!r}, which is not a surface name')
            continue
        definition = definitions.get(name)
        if definition is None:
            found.append(f'{identifier} names undefined surface {name!r}')
            continue
        declared = definition.get('level')
        # A surface whose level was already reported as mistyped is still named here, so this
        # must not hash an arbitrary value either.
        if isinstance(declared, str) and declared in LEVELS and declared != levels[identifier]:
            found.append(
                f'{identifier} prescribes level {levels[identifier]} but surface {name!r} is level {declared}')
    return found


def summarise(levels, surfaces):
    """Counts per surface, and the total sitting on each reach class."""
    definitions, assigned = _shape(surfaces)
    counts = {name: 0 for name in definitions}
    for identifier in levels:
        counts[assigned[identifier]] = counts.get(assigned[identifier], 0) + 1
    reach = {value: 0 for value in REACH_VALUES}
    for name, count in counts.items():
        declared = definitions[name]['reach']
        reach[declared] = reach.get(declared, 0) + count
    return counts, reach


def marker(definition):
    """How the summary describes which pull requests reach this surface."""
    if definition['reach'] == REACH_EVERY:
        return 'every ordinary pull request'
    if definition['reach'] == REACH_SELECTED:
        return f'only when {definition["reachedWhen"]}'
    return 'a separate named session'


def _reject_duplicate_keys(pairs):
    """json.loads keeps the LAST of two identical keys and reports nothing.

    A document assigning one criterion to two different surfaces -- two
    "M1-AC01" entries -- therefore produced no orphan, no level disagreement
    and a published count drawn from whichever entry came last. The same
    collapse hides a surface defined twice. There is no honest verdict about a
    document that says two things, so this refuses it. It is installed on every
    document load(), not on one, because docs/milestones.json is hand-edited
    too and a duplicated "n" or "criteria" key would silently shift every
    positional identifier derived from it.
    """
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f'duplicate key {key!r} in one JSON object')
        seen[key] = value
    return seen


def load(path):
    try:
        return json.loads((ROOT / path).read_text(encoding='utf-8'),
                          object_pairs_hook=_reject_duplicate_keys)
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
        counts, reach = summarise(levels, surfaces)
        definitions = surfaces['surfaces']
        total = len(levels)
        print(f'Execution surfaces agree with {MILESTONES} for all {total} criteria.')
        for name in sorted(counts, key=lambda k: (-counts[k], k)):
            print(f'  {name:<19} {counts[name]:>3}  level {definitions[name]["level"]}  '
                  f'{marker(definitions[name])}')
        print(f'{reach[REACH_EVERY]} of {total} criteria sit on a surface every ordinary pull '
              f"request reaches, {reach[REACH_SELECTED]} of {total} only when the pull request's "
              f'changed paths select that surface, and {reach[REACH_SEPARATE]} of {total} need a '
              f'separate named session.')
        print('Reachable is not validated: a surface says where a pass could be obtained, never that one was.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
