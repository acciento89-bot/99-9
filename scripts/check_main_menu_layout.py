#!/usr/bin/env python3
"""Source guard for the observed main-menu collision; actual GUI checks live in the Godot integration fixture."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'scripts/main_practice.gd').read_text()
def function(name):
    match = re.search(r'^func ' + re.escape(name) + r'\([^\n]*\).*?:\n(.*?)(?=^func |\Z)', SOURCE, re.M | re.S)
    return match.group(1) if match else ''
class MainMenuSourceTests(unittest.TestCase):
    def test_entry_joins_existing_menu_flow_instead_of_root_overlay(self):
        self.assertIn('_practice_build_menu_actions()', function('_ready'))
        self.assertIn('_practice_menu_actions.add_child(_practice_entry)', function('_practice_build_menu_actions'))
        self.assertNotIn('add_child(_practice_entry)', function('_ready'))
        self.assertNotIn('_practice_entry.position', function('_practice_layout'))
        self.assertNotIn('_practice_entry.size =', function('_practice_layout'))
    def test_menu_uses_existing_touch_scroll_and_real_button_objects(self):
        build = function('_practice_build_menu_actions')
        self.assertIn('PracticeTouchScroll.new()', build)
        self.assertIn('action.reparent(_practice_menu_actions)', build)
        self.assertIn('menu_layer.add_child(_practice_menu_scroll)', build)
        layout = function('_practice_menu_layout')
        for required in ['available.size', 'get_combined_minimum_size()', 'custom_minimum_size', '_practice_menu_footer_offsets']:
            self.assertIn(required, layout)
        self.assertNotIn('.pressed.connect', build, 'Keep existing five callbacks on their actual controls')
    def test_entry_label_follows_existing_practice_language(self):
        self.assertNotIn('PRÄZISIONSTRAINING / PRECISION PRACTICE', SOURCE)
        self.assertIn('_practice_t("PRÄZISIONSTRAINING", "PRECISION PRACTICE")', function('_practice_entry_visibility'))
        self.assertIn('_practice_entry.pressed.connect(_practice_open_menu)', function('_ready'))
        self.assertIn('waiting_for_interstitial_close', function('_practice_entry_visibility'))
if __name__ == '__main__':
    unittest.main()
