import copy
from pathlib import Path
import sys
import unittest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from package import validate_routers


class RoutesTest(unittest.TestCase):
    def setUp(self):
        self.routes = yaml.safe_load((Path(__file__).resolve().parents[1] / 'src/routers.yml').read_text())

    def test_current_flat_page(self):
        validate_routers(yaml.safe_dump(self.routes))

    def test_rejects_the_previous_duplicate_application_group(self):
        routes = {'routers': [{'id': 'com-ictrek-gitlab', 'kind': 'group', 'children': self.routes['routers']}]}
        with self.assertRaises(ValueError):
            validate_routers(yaml.safe_dump(routes))

    def test_rejects_an_entry_that_bypasses_language_sync(self):
        routes = copy.deepcopy(self.routes)
        routes['routers'][0]['iframe-src'] = '/app/com.ictrek.gitlab/-/vos/sign_in'
        with self.assertRaises(ValueError):
            validate_routers(yaml.safe_dump(routes))


if __name__ == '__main__':
    unittest.main()
