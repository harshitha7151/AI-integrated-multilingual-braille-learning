import copy
import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault(
    "RESONANT_JWT_SECRET",
    "resonant-test-only-jwt-secret-never-use-in-production",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from braille_mapping_registry import (
    REGISTRY_VERSION,
    mapping_for_skill,
    mapping_records,
    validate_mapping_records,
)


class BrailleMappingRegistryTests(unittest.TestCase):
    def test_registry_is_versioned_multilingual_and_curriculum_linked(self):
        records = mapping_records()
        self.assertEqual({row["language"] for row in records}, {"English", "Hindi", "Kannada"})
        self.assertTrue(all(row["registry_version"] == REGISTRY_VERSION for row in records))
        english_a = mapping_for_skill("english-letter-a", "English")
        hindi_a = mapping_for_skill("hi-bharati-अ", "Hindi")
        kannada_a = mapping_for_skill("kn-bharati-ಅ", "Kannada")
        self.assertEqual(english_a["dot_positions"], [[1]])
        self.assertEqual(hindi_a["braille_cells"], [1])
        self.assertEqual(kannada_a["braille_cells"], [1])

    def test_duplicate_and_conflicting_mappings_are_rejected(self):
        records = mapping_records()
        duplicate = [*records, copy.deepcopy(records[0])]
        with self.assertRaisesRegex(ValueError, "duplicate_braille_mapping_id"):
            validate_mapping_records(duplicate)

        conflict = copy.deepcopy(records)
        changed = copy.deepcopy(conflict[0])
        changed["mapping_id"] += "-conflict"
        changed["braille_cells"] = [63]
        conflict.append(changed)
        with self.assertRaisesRegex(ValueError, "conflicting_braille_mapping"):
            validate_mapping_records(conflict)


if __name__ == "__main__":
    unittest.main()

