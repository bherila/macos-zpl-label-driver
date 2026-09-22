import contextlib
import importlib.util
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


def _module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


surfaces = _module('check_test_surfaces')
ci_scope = _module('ci_scope')

PLAN = 'docs/VALIDATION-PLAN.md'
# How the plan's "Which PRs reach it" column spells each reach value. The column is part of
# the published claim, so a row whose prose and whose map entry disagree is a finding here.
REACH_COLUMN = {
    'every ordinary PR': surfaces.REACH_EVERY,
    'only Swift-affecting PRs': surfaces.REACH_SELECTED,
    'none': surfaces.REACH_SEPARATE,
}
# Each figure the plan publishes in prose, and the sentence fragment that carries it.
PUBLISHED_SENTENCE = {
    surfaces.REACH_EVERY:
        'of {total} criteria sit on a surface every ordinary pull request reaches',
    surfaces.REACH_SELECTED:
        "of {total} only when the pull request's changed paths select that surface",
    surfaces.REACH_SEPARATE:
        'of {total} need a separate named session',
}


def surface(level, reach=surfaces.REACH_EVERY, condition=None):
    definition = {
        'level': level,
        'runsOn': 'somewhere',
        'reach': reach,
        'establishes': 'something',
        'doesNotEstablish': 'something else',
    }
    if condition is not None:
        definition['reachedWhen'] = condition
    return definition


def milestones(*levels):
    """One milestone numbered 0 whose criteria carry the given levels, in order."""
    return [{'n': 0, 'criteria': [[f'Title {i}', level, 'text'] for i, level in enumerate(levels, 1)]}]


def document(criteria, definitions=None, schema=1):
    return {
        'schemaVersion': schema,
        'surfaces': definitions if definitions is not None else {
            'automated': surface('A'),
            'gui': surface('I', reach=surfaces.REACH_SEPARATE),
        },
        'criteria': criteria,
    }


def published_plan():
    return (surfaces.ROOT / PLAN).read_text(encoding='utf-8')


def published_totals(text, total):
    """The reach figures the plan states in prose, read out of the plan itself.

    Returns {reach value: stated count}. Each fragment must occur exactly once
    carrying exactly one figure, so a second contradicting sentence is a failure
    rather than something the first match hides.
    """
    flat = ' '.join(text.split())
    stated = {}
    for value, fragment in PUBLISHED_SENTENCE.items():
        wanted = fragment.format(total=total)
        occurrences = [
            part for part in flat.split(wanted)[:-1] if part.rstrip().rsplit(' ', 1)[-1].isdigit()]
        if flat.count(wanted) != 1 or len(occurrences) != 1:
            raise AssertionError(
                f'{PLAN} states {flat.count(wanted)} figures for {value!r}, not exactly one')
        stated[value] = int(occurrences[0].rstrip().rsplit(' ', 1)[-1])
    return stated


# Words too ordinary to carry a location claim. Every other word of the plan's "Where a pass
# can be obtained" cell must appear in the map's runsOn for that surface, which is what makes
# the published cell an abbreviation of the map rather than a second, independent claim.
LOCATION_STOPWORDS = frozenset('a an the and or of on in with that it its is to for by as'.split())


def location_words(cell):
    """The claim-carrying words of a location cell, for comparison against the map.

    Lowercased and split on every non-alphanumeric character, so `macos-26`, backticks and
    `scripts/run-accelerator-checks.py` all reduce to the words they are built from and the
    plan's typography never decides the verdict.
    """
    return {word for word in re.split(r'[^0-9a-z]+', cell.lower())
            if word and word not in LOCATION_STOPWORDS}


def published_rows(text):
    """The plan's per-surface table rows: name -> (level, location, reach column, stated count).

    Every one of the five content cells is returned, because every one of them is a published
    claim and the caller compares all five. The location cell was read into `_where` and
    dropped, so retyping `macos-native`'s location as the named GC420d left the regression
    green while the plan and the map contradicted each other about where a pass can be
    obtained -- the same defect as the duplicate row below, a field the parser touches and
    then does not check. The two cells outside the pipes are asserted empty rather than
    returned, and the header and separator lines carry no backticked name or digit count, so
    they are skipped as non-rows rather than compared.

    A repeated surface name is a failure, not an overwrite. `rows[name] = ...`
    kept the last of two rows for the same surface, so duplicating a row left a
    13-entry dict still summing to 90 and every assertion below green while the
    rendered table showed the surface twice with two different counts -- a
    parser that validates every row only if no row appears twice.
    """
    rows = {}
    for line in text.split('\n'):
        cells = [cell.strip() for cell in line.strip().split('|')]
        if len(cells) != 7 or cells[0] or cells[-1]:
            continue
        name, level, where, reach_column, count = cells[1:6]
        if not (name.startswith('`') and name.endswith('`')) or not count.isdigit():
            continue
        name = name.strip('`')
        if name in rows:
            raise AssertionError(f'{PLAN} publishes more than one table row for {name!r}')
        rows[name] = (level, where, reach_column, int(count))
    return rows


class PrescribedLevelTests(unittest.TestCase):
    """Identifiers are positional; docs/milestones.json stores none of its own."""

    def test_identifiers_are_derived_from_position_and_zero_padded(self):
        self.assertEqual(
            surfaces.prescribed_levels(milestones('A', 'C', 'I')),
            {'M0-AC01': 'A', 'M0-AC02': 'C', 'M0-AC03': 'I'},
        )

    def test_tenth_criterion_does_not_collide_with_the_first(self):
        levels = surfaces.prescribed_levels(milestones(*(['A'] * 11)))
        self.assertIn('M0-AC10', levels)
        self.assertIn('M0-AC11', levels)
        self.assertEqual(len(levels), 11)

    def test_an_unknown_level_cannot_be_evaluated(self):
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.prescribed_levels(milestones('A', 'Z'))


class MalformedDocumentTests(unittest.TestCase):
    """A shape no verdict can be read from is Unevaluable, never a disagreement.

    main() catches Unevaluable and exits 2. Anything else escapes as a traceback and
    exits 1, the code that means the map and the milestones disagree -- a false
    verdict about content, produced by a file that had no content to judge.
    """

    def test_a_null_surface_definition_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable) as caught:
            surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': None}))
        self.assertIn('NoneType', str(caught.exception))

    def test_a_list_surface_definition_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': ['A']}))

    def test_a_document_that_is_not_an_object_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.findings(levels, [{'schemaVersion': 1}])

    def test_a_surfaces_map_that_is_not_an_object_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.findings(levels, document({'M0-AC01': 'automated'}, ['automated']))

    def test_a_criteria_map_that_is_not_an_object_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.findings(levels, document(['M0-AC01']))

    def test_an_unsupported_schema_version_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.findings(levels, document({'M0-AC01': 'automated'}, schema=2))

    def test_a_schema_version_equal_to_one_but_not_an_integer_is_refused(self):
        """`!= SUPPORTED_SCHEMA` accepted every value Python calls equal to 1.

        `True == 1` and `1.0 == 1`, so a hand-edited "schemaVersion": true declared no
        schema version at all and still produced no finding and exit 0 -- the document
        was read under a schema it never claimed. The bool exclusion was already on `n`
        in prescribed_levels() while this stayed a bare `!=`. Each value is named so the
        fix cannot be a single `is not True`, and the message must quote what was found
        rather than the version the checker supports.
        """
        levels = surfaces.prescribed_levels(milestones('A'))
        for version in (True, 1.0):
            with self.subTest(version=version):
                with self.assertRaises(surfaces.Unevaluable) as caught:
                    surfaces.findings(levels, document({'M0-AC01': 'automated'}, schema=version))
                self.assertIn('schemaVersion', str(caught.exception))
                self.assertIn(repr(version), str(caught.exception))

    def test_the_integer_one_is_still_accepted(self):
        """The bound from the other side: the real version must not become a refusal."""
        levels = surfaces.prescribed_levels(milestones('A'))
        self.assertEqual(
            surfaces.findings(levels, document({'M0-AC01': 'automated'}, schema=1)), [])

    def test_a_falsey_surfaces_map_is_refused_rather_than_defaulted_away(self):
        """`surfaces.get("surfaces") or {}` replaced every falsey value before the shape
        check could see it, so "surfaces": null was read as an empty object and reported as
        ninety criteria with no surface -- exit 1, "the map and the milestones disagree",
        about a file that declared nothing. Each falsey shape is named so that the fix
        cannot be a single `is not None`.
        """
        levels = surfaces.prescribed_levels(milestones('A'))
        for empty in (None, [], '', 0, False):
            for key in ('surfaces', 'criteria'):
                broken = document({'M0-AC01': 'automated'})
                broken[key] = empty
                with self.subTest(value=empty, key=key):
                    with self.assertRaises(surfaces.Unevaluable) as caught:
                        surfaces.findings(levels, broken)
                    self.assertIn(f'"{key}"', str(caught.exception))

    def test_an_absent_map_is_refused_and_says_which_key_is_missing(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        for key in ('surfaces', 'criteria'):
            broken = document({'M0-AC01': 'automated'})
            del broken[key]
            with self.subTest(key=key):
                with self.assertRaises(surfaces.Unevaluable) as caught:
                    surfaces.findings(levels, broken)
                self.assertEqual(str(caught.exception), f'the document omits "{key}"')

    def test_an_empty_object_is_still_evaluated_and_not_refused(self):
        """The bound from the other side: {} has a shape, so it is a finding, never a refusal."""
        levels = surfaces.prescribed_levels(milestones('A'))
        found = surfaces.findings(levels, document({}, {}))
        self.assertEqual(found, ['M0-AC01 has no declared execution surface'])

    def test_a_malformed_map_exits_two_rather_than_one(self):
        """The published contract: 2 means no verdict, 1 means the two files disagree.

        findings() raising Unevaluable is only half the claim; main() must map it to the
        exit code the docstring promises, and nothing else may escape on the way.
        """
        real = surfaces.load
        milestone_document = real(surfaces.MILESTONES)

        def fake(path):
            return milestone_document if path == surfaces.MILESTONES else {
                'schemaVersion': 1, 'surfaces': None, 'criteria': None}

        argv = sys.argv
        surfaces.load, sys.argv = fake, ['check_test_surfaces.py']
        try:
            with contextlib.redirect_stderr(io.StringIO()) as captured:
                status = surfaces.main()
        finally:
            surfaces.load, sys.argv = real, argv
        self.assertEqual(status, 2)
        self.assertIn('Cannot evaluate', captured.getvalue())

    def test_a_duplicate_json_key_cannot_be_evaluated(self):
        """json.loads keeps the last of two identical keys and says nothing.

        Two "M1-AC01" entries assigning different surfaces produced no orphan, no level
        disagreement and a count drawn from whichever came last. Exercised through load()
        so the hook is proved installed, and on both documents load() reads.
        """
        root = surfaces.ROOT
        with tempfile.TemporaryDirectory() as directory:
            for name, text in (
                    ('surfaces.json', '{"criteria": {"M1-AC01": "gui", "M1-AC01": "physical"}}'),
                    ('milestones.json', '[{"n": 0, "criteria": [], "criteria": []}]')):
                (Path(directory) / name).write_text(text, encoding='utf-8')
            surfaces.ROOT = Path(directory)
            try:
                for name, key in (('surfaces.json', 'M1-AC01'), ('milestones.json', 'criteria')):
                    with self.subTest(document=name):
                        with self.assertRaises(surfaces.Unevaluable) as caught:
                            surfaces.load(name)
                        self.assertIn(f"duplicate key '{key}'", str(caught.exception))
            finally:
                surfaces.ROOT = root

    def test_a_unique_key_document_still_loads(self):
        """The bound from the other side: the hook must not refuse an ordinary document."""
        self.assertEqual(surfaces.load(surfaces.SURFACES)['schemaVersion'], 1)


class MistypedFieldTests(unittest.TestCase):
    """A field of the wrong type is reported, never raised.

    `level` reached `in LEVELS`, a set, so "level": [] raised `TypeError: unhashable
    type` past main()'s Unevaluable handler and printed a traceback. The guard is the
    whole set of fields rather than the one that was named: `reach` is later used as a
    dictionary key, and the rest are published prose.
    """

    def test_every_required_field_is_type_checked_before_use(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        for key in sorted(surfaces.REQUIRED_SURFACE_KEYS):
            for value in ([], {}, None, 7, True, '', '   '):
                with self.subTest(field=key, value=value):
                    broken = surface('A')
                    broken[key] = value
                    found = surfaces.findings(
                        levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
                    self.assertEqual(found, [
                        f"surface 'automated' declares {key} as something other than a "
                        'non-empty string'])

    def test_an_unhashable_level_on_a_named_surface_is_still_only_a_finding(self):
        """The criteria loop looks the same definition up again and must not hash it either."""
        levels = surfaces.prescribed_levels(milestones('A'))
        broken = surface('A')
        broken['level'] = []
        found = surfaces.findings(
            levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
        self.assertEqual(len(found), 1)
        self.assertIn('level', found[0])

    def test_a_milestone_document_of_the_wrong_shape_cannot_be_evaluated(self):
        """prescribed_levels reads four fields of its own; each is checked before use."""
        for broken in (
                {'n': 0},
                [{'criteria': [['t', 'A', 'd']]}],
                [{'n': 0, 'criteria': {'a': 1}}],
                [{'n': 0, 'criteria': [['title only']]}],
                [{'n': 0, 'criteria': [['title', [], 'd']]}],
                [{'n': 0, 'criteria': [['title', {}, 'd']]}],
                [['n', 0]]):
            with self.subTest(document=broken):
                with self.assertRaises(surfaces.Unevaluable):
                    surfaces.prescribed_levels(broken)


class FindingTests(unittest.TestCase):
    """Each test names the single disagreement it introduces."""

    def test_an_agreeing_map_reports_nothing(self):
        levels = surfaces.prescribed_levels(milestones('A', 'I'))
        found = surfaces.findings(levels, document({'M0-AC01': 'automated', 'M0-AC02': 'gui'}))
        self.assertEqual(found, [])

    def test_a_criterion_with_no_surface_is_reported(self):
        levels = surfaces.prescribed_levels(milestones('A', 'I'))
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}))
        self.assertEqual(found, ['M0-AC02 has no declared execution surface'])

    def test_a_surface_for_a_criterion_that_does_not_exist_is_reported(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        found = surfaces.findings(levels, document({'M0-AC01': 'automated', 'M9-AC01': 'automated'}))
        self.assertEqual(len(found), 1)
        self.assertIn('M9-AC01', found[0])
        self.assertIn('is not a criterion', found[0])

    def test_an_undefined_surface_name_is_reported(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        found = surfaces.findings(levels, document({'M0-AC01': 'imaginary'}))
        self.assertEqual(found, ["M0-AC01 names undefined surface 'imaginary'"])

    def test_a_surface_name_that_is_not_a_string_is_reported(self):
        """A list is unhashable, so looking it up would raise rather than report."""
        levels = surfaces.prescribed_levels(milestones('A'))
        found = surfaces.findings(levels, document({'M0-AC01': ['automated']}))
        self.assertEqual(found, ["M0-AC01 names ['automated'], which is not a surface name"])

    def test_a_surface_whose_level_contradicts_the_criterion_is_reported(self):
        """The invariant this file exists for: a surface implies a level."""
        levels = surfaces.prescribed_levels(milestones('I'))
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}))
        self.assertEqual(found, ["M0-AC01 prescribes level I but surface 'automated' is level A"])

    def test_an_incomplete_surface_definition_is_reported(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        broken = dict(surface('A'))
        del broken['doesNotEstablish']
        del broken['runsOn']
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
        self.assertEqual(found, ["surface 'automated' omits doesNotEstablish, runsOn"])

    def test_a_surface_declaring_an_unknown_level_is_reported(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': surface('Z')}))
        self.assertEqual(found, ["surface 'automated' declares unknown level 'Z'"])

    def test_a_reach_outside_the_closed_set_is_reported(self):
        """The reach decides the published count, so an unrecognised value is refused."""
        levels = surfaces.prescribed_levels(milestones('A'))
        broken = dict(surface('A'))
        broken['reach'] = 'sometimes'
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
        self.assertEqual(found, [
            "surface 'automated' declares reach 'sometimes', which is not one of "
            'every-pull-request, selected-pull-requests, separate-session'])

    def test_a_bare_true_is_neither_accepted_nor_counted_as_reachable(self):
        """Why a closed set and not a flag: JSON true is truthy and truthiness would believe it."""
        levels = surfaces.prescribed_levels(milestones('I'))
        broken = dict(surface('I', reach=surfaces.REACH_SEPARATE))
        broken['reach'] = True
        with_bare_true = document({'M0-AC01': 'gui'}, {'gui': broken})
        self.assertEqual(len(surfaces.findings(levels, with_bare_true)), 1)
        self.assertEqual(surfaces.summarise(levels, with_bare_true)[1][surfaces.REACH_EVERY], 0)

    def test_a_conditional_surface_that_names_no_condition_is_reported(self):
        """selected-pull-requests without reachedWhen says some PRs reach it but not which."""
        levels = surfaces.prescribed_levels(milestones('A'))
        broken = surface('A', reach=surfaces.REACH_SELECTED)
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
        self.assertEqual(found, [
            "surface 'automated' is reached by selected pull requests but its reachedWhen "
            'names no condition'])

    def test_a_blank_condition_is_not_a_condition(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        broken = surface('A', reach=surfaces.REACH_SELECTED, condition='   ')
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
        self.assertEqual(len(found), 1)
        self.assertIn('names no condition', found[0])

    def test_an_unconditional_surface_that_still_names_a_condition_is_reported(self):
        """A leftover condition on an every-pull-request surface is two answers, not one."""
        levels = surfaces.prescribed_levels(milestones('A'))
        broken = surface('A', condition='the wind is right')
        found = surfaces.findings(levels, document({'M0-AC01': 'automated'}, {'automated': broken}))
        self.assertEqual(found, [
            "surface 'automated' declares reach every-pull-request yet names the reachedWhen "
            "condition 'the wind is right'"])

    def test_a_level_r_surface_may_declare_per_pull_request_reach(self):
        """Deliberately allowed: an earlier revision refused this, and the refusal was wrong.

        The rule read "no level H or R surface may claim per-pull-request reach",
        justified by CI reaching no private printer and no release gate. But a level
        says what a pass establishes, not whether a pull request may obtain one:
        level R describes an installation and distribution lifecycle, not the act of
        publishing, and a secret-free pull request could exercise an ad-hoc
        candidate's lifecycle without publishing anything. The rule was the level and
        session conflation this whole map exists to remove, so it is gone. A
        constraint of that kind belongs on a declared effect, and this map declares
        no effects.
        """
        levels = surfaces.prescribed_levels(milestones('R', 'H'))
        found = surfaces.findings(levels, document(
            {'M0-AC01': 'release', 'M0-AC02': 'physical'},
            {'release': surface('R'), 'physical': surface('H')}))
        self.assertEqual(found, [])

    def test_an_empty_map_reports_every_criterion_rather_than_passing(self):
        """An absent map is the failure mode a truthful checker must not read as agreement."""
        levels = surfaces.prescribed_levels(milestones('A', 'C', 'I'))
        found = surfaces.findings(levels, document({}))
        self.assertEqual(len(found), 3)


class SummaryTests(unittest.TestCase):
    def test_each_reach_class_is_counted_separately(self):
        levels = surfaces.prescribed_levels(milestones('A', 'A', 'I', 'I'))
        definitions = {
            'automated': surface('A'),
            'gui': surface('I', reach=surfaces.REACH_SEPARATE),
            'macos-native': surface('I', reach=surfaces.REACH_SELECTED, condition='Swift changed'),
        }
        counts, reach = surfaces.summarise(levels, document({
            'M0-AC01': 'automated', 'M0-AC02': 'automated',
            'M0-AC03': 'gui', 'M0-AC04': 'macos-native'}, definitions))
        self.assertEqual(counts, {'automated': 2, 'gui': 1, 'macos-native': 1})
        self.assertEqual(reach, {
            surfaces.REACH_EVERY: 2,
            surfaces.REACH_SELECTED: 1,
            surfaces.REACH_SEPARATE: 1,
        })

    def test_a_conditional_surface_is_described_by_its_own_condition(self):
        self.assertEqual(
            surfaces.marker(surface('I', reach=surfaces.REACH_SELECTED, condition='Swift changed')),
            'only when Swift changed')
        self.assertEqual(surfaces.marker(surface('A')), 'every ordinary pull request')
        self.assertEqual(surfaces.marker(surface('H', reach=surfaces.REACH_SEPARATE)),
                         'a separate named session')


class RepositoryTests(unittest.TestCase):
    """The committed map must agree with the committed criteria."""

    def test_the_committed_map_agrees_with_the_committed_milestones(self):
        levels = surfaces.prescribed_levels(surfaces.load(surfaces.MILESTONES))
        self.assertEqual(surfaces.findings(levels, surfaces.load(surfaces.SURFACES)), [])

    def test_every_criterion_is_classified(self):
        levels = surfaces.prescribed_levels(surfaces.load(surfaces.MILESTONES))
        self.assertEqual(len(surfaces.load(surfaces.SURFACES)['criteria']), len(levels))


class CommittedClassificationTests(unittest.TestCase):
    """Rows the 2026-09-18 ledger classified wrongly, re-derived from the specs.

    Each names the sentence that settles it, so a later edit back to the ledger's
    answer fails here rather than silently restoring a wrong reachable count.
    """

    def setUp(self):
        self.document = surfaces.load(surfaces.SURFACES)
        self.assigned = self.document['criteria']
        self.definitions = self.document['surfaces']

    def assert_separate_session(self, name, level):
        self.assertEqual(self.definitions[name]['reach'], surfaces.REACH_SEPARATE)
        self.assertEqual(self.definitions[name]['level'], level)

    def test_dedicated_ci_experiments_are_not_ordinary_pull_request_config(self):
        """M0 tests: one documentation-only change, one intentionally failing test, a fork PR."""
        self.assertEqual(self.assigned['M0-AC06'], 'config-experiment')
        self.assertEqual(self.assigned['M0-AC09'], 'config-experiment')
        self.assert_separate_session('config-experiment', 'C')
        self.assertEqual(self.definitions['config']['reach'], surfaces.REACH_EVERY)

    def test_repository_creation_precedes_the_pull_request_under_review(self):
        """M0-AC01: content preserved or absence established BEFORE creation.

        The M0 matrix reaches it through a bootstrap rehearsal in a fresh temporary
        checkout and a collision check against an existing repository. Neither is the
        pull request being reviewed, which is made against a repository that exists.
        """
        self.assertEqual(self.assigned['M0-AC01'], 'bootstrap')
        self.assert_separate_session('bootstrap', 'C')

    def test_live_repository_settings_are_not_committed_files(self):
        """M0-AC10: vulnerability-reporting availability and branch protection are settings.

        A pull request job holds a read-only token and reads files, so it cannot observe
        them at all; the observation needs separate maintainer authority.
        """
        self.assertEqual(self.assigned['M0-AC10'], 'repo-settings')
        self.assert_separate_session('repo-settings', 'C')
        self.assertNotEqual(self.definitions['repo-settings']['runsOn'],
                            self.definitions['bootstrap']['runsOn'])

    def test_config_holds_only_claims_the_reviewed_pull_request_can_make(self):
        """What is left on config after the sweep: committed files, and this PR's own run."""
        self.assertEqual(sorted(k for k, v in self.assigned.items() if v == 'config'),
                         ['M0-AC02', 'M0-AC05', 'M1-AC12', 'M6-AC13'])

    def test_hosted_macos_is_not_reached_by_a_documentation_only_pull_request(self):
        """The gate is real: ci.yml runs swift-macos-arm64 only when ci_scope says so."""
        self.assertEqual(self.definitions['macos-native']['reach'], surfaces.REACH_SELECTED)
        self.assertTrue(self.definitions['macos-native']['reachedWhen'].strip())
        self.assertFalse(ci_scope.needs_swift(['docs/VALIDATION-PLAN.md']))
        self.assertFalse(ci_scope.needs_swift(['README.md', 'docs/BUILDING.md']))
        self.assertTrue(ci_scope.needs_swift(['docs/test-surfaces.json']))
        self.assertTrue(ci_scope.needs_swift(['scripts/check_test_surfaces.py']))
        workflow = (surfaces.ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        self.assertIn("if: needs.repository.outputs.swift_changed == 'true'", workflow)

    def test_performance_baselines_are_not_hosted_ci(self):
        """M2 spec: shared hosted-runner timing is informational, not a precise SLA."""
        self.assertEqual(self.assigned['M2-AC12'], 'benchmark')
        self.assertEqual(self.assigned['M6-AC09'], 'benchmark')
        self.assert_separate_session('benchmark', 'I')

    def test_finishing_qualification_is_not_the_tear_off_printer(self):
        """M3 tests: finishing qualification names an approved ACCESSORY target."""
        self.assertEqual(self.assigned['M3-AC10'], 'accessory')
        self.assertEqual(self.assigned['M6-AC06'], 'accessory')
        self.assert_separate_session('accessory', 'H')
        self.assertNotEqual(self.definitions['accessory']['runsOn'],
                            self.definitions['physical']['runsOn'])

    def test_optional_integration_claims_have_no_single_session(self):
        """M6-AC11: each advertised IPP/Intel/extra-transport claim needs its own evidence."""
        self.assertEqual(self.assigned['M6-AC11'], 'per-claim')
        self.assert_separate_session('per-claim', 'I')
        self.assertEqual([k for k, v in self.assigned.items() if v == 'per-claim'], ['M6-AC11'])

    def test_cancellation_needs_the_scheduler_not_a_hosted_run(self):
        """M1 spec: cancellation in scheduler context; a terminal invocation is insufficient."""
        self.assertEqual(self.assigned['M1-AC09'], 'installed')

    def test_diagnostic_export_needs_the_local_gui_review(self):
        """M5 matrix: sensitive-data-negative diagnostic export checks are a local GUI review."""
        self.assertEqual(self.assigned['M5-AC09'], 'gui')

    def test_the_published_reachable_figure_is_the_one_the_map_produces(self):
        """Read the figures out of docs/VALIDATION-PLAN.md; do not restate them here.

        The previous version compared summarise() with a hard-coded 43 and named the
        plan only in its own docstring, so editing the plan's sentence or any count in
        its table left this green -- the map compared against itself. It now parses the
        published prose and the published table and fails when either drifts.
        """
        levels = surfaces.prescribed_levels(surfaces.load(surfaces.MILESTONES))
        counts, reach = surfaces.summarise(levels, self.document)
        plan = published_plan()

        for value, stated in published_totals(plan, len(levels)).items():
            self.assertEqual(stated, reach[value],
                             f'{PLAN} publishes {stated} for {value}, the map produces {reach[value]}')
        self.assertEqual(sum(reach.values()), len(levels))

        rows = published_rows(plan)
        self.assertEqual(sorted(rows), sorted(counts))
        for name, (level, _where, column, stated) in sorted(rows.items()):
            self.assertEqual(stated, counts[name],
                             f'{PLAN} publishes {stated} criteria on {name}, the map has {counts[name]}')
            self.assertEqual(level, self.definitions[name]['level'])
            self.assertEqual(REACH_COLUMN[column], self.definitions[name]['reach'],
                             f'{PLAN} describes {name} as {column!r}')
        self.assertEqual(sum(stated for *_, stated in rows.values()), len(levels))

    def test_the_published_where_column_agrees_with_the_map(self):
        """The location cell is a claim, so it is compared rather than parsed and dropped.

        published_rows() read the central "Where a pass can be obtained" cell into `_where`
        and discarded it, so the level, the reach column and the count were checked while the
        one column the surface exists to answer was not. Retyping `macos-native`'s location
        as the named GC420d over USB therefore left this suite green with the plan telling an
        agent to reach for a printer that the map says obtains nothing here.

        The published cell is an abbreviation of the map, not a second claim, so every
        claim-carrying word of it must appear in that surface's runsOn. Comparing the two
        strings outright would only force the table to carry the map's full prose.
        """
        rows = published_rows(published_plan())
        self.assertEqual(sorted(rows), sorted(self.definitions))
        for name, (_level, where, _column, _stated) in sorted(rows.items()):
            self.assertTrue(location_words(where), f'{PLAN} gives {name} an empty location')
            stray = location_words(where) - location_words(self.definitions[name]['runsOn'])
            self.assertEqual(
                stray, set(),
                f'{PLAN} locates {name} with {sorted(stray)}, which its runsOn does not say')

    def test_the_a_level_rows_are_split_by_the_job_that_actually_runs_them(self):
        """The correction this revision exists for, and the claim it replaces.

        A single `automated` surface claimed every-ordinary-PR reach because its portable
        tests run in the Linux container on any branch. That is a local run. In CI the
        always-running job runs the Python checkers and scripts/tests and no Swift at all;
        `swift test --package-path Packages/LabelCore` and run-accelerator-checks.py are
        reached only through scripts/ci-swift.sh in the gated macOS job, so a Markdown-only
        pull request exercised no Swift-backed A row while the map said it exercised thirty.
        The assertion is on the workflow, not on the map restating itself.
        """
        self.assertNotIn('automated', self.definitions)
        preflight = self.definitions['automated-preflight']
        swift = self.definitions['automated-swift']
        self.assertEqual(preflight['level'], 'A')
        self.assertEqual(swift['level'], 'A')
        self.assertEqual(preflight['reach'], surfaces.REACH_EVERY)
        self.assertEqual(swift['reach'], surfaces.REACH_SELECTED)
        # The same swift_changed output gates both, so the same condition must describe both.
        self.assertEqual(swift['reachedWhen'], self.definitions['macos-native']['reachedWhen'])

        workflow = (surfaces.ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        script = (surfaces.ROOT / 'scripts/ci-swift.sh').read_text(encoding='utf-8')
        self.assertNotIn('swift test', workflow)
        self.assertNotIn('run-accelerator-checks', workflow)
        self.assertIn('bash scripts/ci-swift.sh', workflow)
        self.assertIn('run-accelerator-checks.py', script)
        self.assertIn('swift test', script)
        self.assertIn('"swift","test","--package-path","Packages/LabelCore"', ''.join(
            (surfaces.ROOT / 'scripts/run-accelerator-checks.py')
            .read_text(encoding='utf-8').split()))
        self.assertFalse(ci_scope.needs_swift(['docs/VALIDATION-PLAN.md']))

    def test_the_preflight_rows_are_the_ones_the_python_checkers_decide(self):
        """Named individually: a row moved back without its evidence moving fails here.

        Each of these four was re-derived by naming the program that produces its evidence,
        not by grepping for a language. M0-AC07 and M0-AC08 are check_repo.py; M0-AC11 is
        check_reference_target.py plus the Package.swift assertions check_repo.py makes by
        reading the manifest as text; M6-AC01 is traceability_report.py and
        evidence_currency.py. None is produced by a Darwin-gated shell script, which is the
        property that moved M5-AC12 off this surface.
        """
        self.assertEqual(
            sorted(k for k, v in self.assigned.items() if v == 'automated-preflight'),
            ['M0-AC07', 'M0-AC08', 'M0-AC11', 'M6-AC01'])
        swift_backed = sorted(k for k, v in self.assigned.items() if v == 'automated-swift')
        self.assertEqual(len(swift_backed), 23)
        self.assertIn('M0-AC03', swift_backed)
        self.assertIn('M2-AC13', swift_backed)
        self.assertNotIn('automated', set(self.assigned.values()))
        # The preflight job's own step list: these four are reachable because the always-running
        # job runs these programs, and it runs no Darwin-gated script at all.
        workflow = (surfaces.ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        preflight = workflow.split('  macos:')[0]
        self.assertIn('python3 scripts/check_repo.py', preflight)
        self.assertIn('python3 -m unittest discover -s scripts/tests', preflight)
        for darwin_only in ('scripts/build-local-app.sh', 'scripts/host-preflight.sh',
                            'scripts/sign-local-diagnostic.sh'):
            self.assertNotIn(darwin_only, preflight)

    def test_the_macos_only_a_level_rows_are_not_on_a_portable_surface(self):
        """M5-AC12, M2-AC05 and M3-AC03: level A evidence no Linux session can produce.

        Two different mistakes put them on portable surfaces and both came from naming
        something other than the executor. M5-AC12 was on automated-preflight because
        check_native_artifacts.py carries signing-mode rules in Python -- but that module
        validates captures, its unit tests feed it synthetic ones, and the default and the
        Developer-ID refusal are decided by scripts/build-local-app.sh, which exits unless
        `uname -s` is Darwin and which only scripts/ci-swift.sh invokes. A grep across
        Packages/*/Sources and Packages/*/Tests for a Swift implementation returns nothing,
        which is a correct answer to the wrong question. M2-AC05 and M3-AC03 were on
        automated-swift, a surface whose runsOn offers a portable Linux session, while the
        four test files they actually bind are under Packages/LabelMac, which does not build
        on Linux.

        The assertions are on the scripts and on docs/ACCEPTANCE-EVIDENCE.json, not on the
        map restating itself.
        """
        macos_only = sorted(k for k, v in self.assigned.items() if v == 'automated-macos')
        self.assertEqual(macos_only, ['M2-AC05', 'M3-AC03', 'M5-AC12'])
        surface = self.definitions['automated-macos']
        self.assertEqual(surface['level'], 'A')
        self.assertEqual(surface['reach'], surfaces.REACH_SELECTED)
        self.assertEqual(surface['reachedWhen'], self.definitions['macos-native']['reachedWhen'])
        # Same host, different prescribed level, so they cannot be one surface.
        self.assertNotEqual(surface['runsOn'], self.definitions['macos-native']['runsOn'])

        # M5-AC12's executor: bash, Darwin-gated, called from one place.
        app = (surfaces.ROOT / 'scripts/build-local-app.sh').read_text(encoding='utf-8')
        self.assertIn('signing_mode="local-adhoc"', app)
        self.assertIn('Developer-ID signing is not configured', app)
        self.assertIn('[[ "$(uname -s)" == "Darwin" ]]', app)
        ci_swift = (surfaces.ROOT / 'scripts/ci-swift.sh').read_text(encoding='utf-8')
        self.assertIn('bash scripts/build-local-app.sh', ci_swift)
        callers = sorted(
            path.relative_to(surfaces.ROOT).as_posix()
            for path in (surfaces.ROOT / 'scripts').iterdir()
            if path.is_file() and 'build-local-app.sh' in path.read_text(
                encoding='utf-8', errors='ignore') and path.name != 'build-local-app.sh')
        self.assertEqual(callers, ['scripts/ci-swift.sh'])

        # M2-AC05 and M3-AC03: the evidence the ledger actually binds is under LabelMac, and
        # only ci-swift.sh runs that package's suite.
        self.assertIn('swift test --package-path Packages/LabelMac', ci_swift)
        ledger = json.loads(
            (surfaces.ROOT / 'docs/ACCEPTANCE-EVIDENCE.json').read_text(encoding='utf-8'))
        bound = {record['acceptanceID']: [item['path'] for item in record.get('evidence', [])]
                 for record in ledger['records']}
        for identifier in ('M2-AC05', 'M3-AC03'):
            with self.subTest(identifier=identifier):
                self.assertTrue(
                    any(path.startswith('Packages/LabelMac/') for path in bound[identifier]),
                    f'{identifier} binds no Packages/LabelMac evidence')
        # Every live record was swept, not only the two named: a record citing LabelMac must
        # not be sitting on the portable surface.
        for identifier, paths in sorted(bound.items()):
            if any(path.startswith('Packages/LabelMac/') for path in paths):
                with self.subTest(identifier=identifier):
                    self.assertNotEqual(self.assigned[identifier], 'automated-swift')

    def test_no_surface_is_defined_without_a_criterion_using_it(self):
        self.assertEqual(sorted(self.definitions), sorted(set(self.assigned.values())))


class PublishedTableParsingTests(unittest.TestCase):
    """The parser that reads the plan's table must not lose a row.

    `rows[name] = ...` overwrote a repeated surface, so duplicating a row left the dict
    the right size and the right sum while the rendered table showed the surface twice
    with two different counts. Every assertion about "every table row" was then true of
    every row the parser had kept, which is not the property its name claims.
    """

    TABLE = ('| Surface | Level | Where | Which PRs reach it | Criteria |\n'
             '|---|---|---|---|---|\n'
             '| `alpha` | A | somewhere | every ordinary PR | 4 |\n'
             '| `beta` | I | elsewhere | none | 6 |\n')

    def test_each_row_is_read_once(self):
        self.assertEqual(published_rows(self.TABLE), {
            'alpha': ('A', 'somewhere', 'every ordinary PR', 4),
            'beta': ('I', 'elsewhere', 'none', 6),
        })

    def test_the_location_cell_is_preserved_rather_than_discarded(self):
        """The cell the parser used to read into `_where` and throw away.

        Named on its own so that a later parser cannot quietly drop it again while the
        row count, the level and the reach column all still line up.
        """
        self.assertEqual([row[1] for row in published_rows(self.TABLE).values()],
                         ['somewhere', 'elsewhere'])

    def test_location_words_ignore_typography_but_keep_the_claim(self):
        """Backticks, hyphens and paths must not decide a location comparison."""
        self.assertEqual(location_words('hosted `macos-26` CI'), {'hosted', 'macos', '26', 'ci'})
        self.assertEqual(location_words('the release gate'), {'release', 'gate'})
        self.assertTrue(
            location_words('hosted `macos-26` CI') - location_words('the named GC420d over USB'))

    def test_a_repeated_surface_row_fails_instead_of_overwriting(self):
        duplicated = self.TABLE + '| `alpha` | A | somewhere | every ordinary PR | 30 |\n'
        with self.assertRaises(AssertionError) as caught:
            published_rows(duplicated)
        self.assertIn("'alpha'", str(caught.exception))


if __name__ == '__main__':
    unittest.main()
