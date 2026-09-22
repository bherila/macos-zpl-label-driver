import importlib.util
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('check_test_surfaces', SCRIPTS / 'check_test_surfaces.py')
surfaces = importlib.util.module_from_spec(spec)
spec.loader.exec_module(surfaces)


def surface(level, per_pull_request=True):
    return {
        'level': level,
        'runsOn': 'somewhere',
        'runsPerPullRequest': per_pull_request,
        'establishes': 'something',
        'doesNotEstablish': 'something else',
    }


def milestones(*levels):
    """One milestone numbered 0 whose criteria carry the given levels, in order."""
    return [{'n': 0, 'criteria': [[f'Title {i}', level, 'text'] for i, level in enumerate(levels, 1)]}]


def document(criteria, definitions=None, schema=1):
    return {
        'schemaVersion': schema,
        'surfaces': definitions if definitions is not None else {
            'automated': surface('A'),
            'gui': surface('I', per_pull_request=False),
        },
        'criteria': criteria,
    }


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

    def test_an_unsupported_schema_version_cannot_be_evaluated(self):
        levels = surfaces.prescribed_levels(milestones('A'))
        with self.assertRaises(surfaces.Unevaluable):
            surfaces.findings(levels, document({'M0-AC01': 'automated'}, schema=2))

    def test_an_empty_map_reports_every_criterion_rather_than_passing(self):
        """An absent map is the failure mode a truthful checker must not read as agreement."""
        levels = surfaces.prescribed_levels(milestones('A', 'C', 'I'))
        found = surfaces.findings(levels, document({}))
        self.assertEqual(len(found), 3)


class SummaryTests(unittest.TestCase):
    def test_reachable_counts_only_surfaces_a_pull_request_runs(self):
        levels = surfaces.prescribed_levels(milestones('A', 'A', 'I'))
        counts, reachable = surfaces.summarise(
            levels, document({'M0-AC01': 'automated', 'M0-AC02': 'automated', 'M0-AC03': 'gui'}))
        self.assertEqual(counts, {'automated': 2, 'gui': 1})
        self.assertEqual(reachable, 2)


class RepositoryTests(unittest.TestCase):
    """The committed map must agree with the committed criteria."""

    def test_the_committed_map_agrees_with_the_committed_milestones(self):
        levels = surfaces.prescribed_levels(surfaces.load(surfaces.MILESTONES))
        self.assertEqual(surfaces.findings(levels, surfaces.load(surfaces.SURFACES)), [])

    def test_every_criterion_is_classified(self):
        levels = surfaces.prescribed_levels(surfaces.load(surfaces.MILESTONES))
        self.assertEqual(len(surfaces.load(surfaces.SURFACES)['criteria']), len(levels))


if __name__ == '__main__':
    unittest.main()
