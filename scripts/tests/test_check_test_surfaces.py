import importlib.util
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


def published_rows(text):
    """The plan's per-surface table rows: name -> (level, reach column, stated count)."""
    rows = {}
    for line in text.split('\n'):
        cells = [cell.strip() for cell in line.strip().split('|')]
        if len(cells) != 7 or cells[0] or cells[-1]:
            continue
        name, level, _where, reach_column, count = cells[1:6]
        if not (name.startswith('`') and name.endswith('`')) or not count.isdigit():
            continue
        rows[name.strip('`')] = (level, reach_column, int(count))
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
        for name, (level, column, stated) in sorted(rows.items()):
            self.assertEqual(stated, counts[name],
                             f'{PLAN} publishes {stated} criteria on {name}, the map has {counts[name]}')
            self.assertEqual(level, self.definitions[name]['level'])
            self.assertEqual(REACH_COLUMN[column], self.definitions[name]['reach'],
                             f'{PLAN} describes {name} as {column!r}')
        self.assertEqual(sum(stated for _, _, stated in rows.values()), len(levels))

    def test_no_surface_is_defined_without_a_criterion_using_it(self):
        self.assertEqual(sorted(self.definitions), sorted(set(self.assigned.values())))


if __name__ == '__main__':
    unittest.main()
