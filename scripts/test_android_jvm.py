#!/usr/bin/env python3
"""Regression tests for Android JVM target normalization."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import patch_android


class AndroidJvmTargetTest(unittest.TestCase):
    def check_template(self, kotlin_block):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            android = root / "android"
            app = android / "app"
            app.mkdir(parents=True)
            (android / "gradle.properties").write_text("android.builtInKotlin=true\n")
            (android / "settings.gradle.kts").write_text(
                'plugins {\n    id("org.jetbrains.kotlin.android") version "2.4.0" apply false\n}\n'
            )
            gradle = app / "build.gradle.kts"
            gradle.write_text(
                'plugins {\n    id("org.jetbrains.kotlin.android")\n}\n'
                'android {\n    compileOptions {\n'
                '        sourceCompatibility = JavaVersion.VERSION_17\n'
                '        targetCompatibility = JavaVersion.VERSION_17\n'
                '    }\n}\n' + kotlin_block
            )
            with patch.object(patch_android, "ROOT", root):
                patch_android.patch_agp_kotlin_compat()
                first = gradle.read_text()
                patch_android.patch_agp_kotlin_compat()
                self.assertEqual(first, gradle.read_text())
            self.assertEqual(first.count("kotlin {"), 1)
            self.assertEqual(first.count("JvmTarget.JVM_17"), 1)
            self.assertNotIn("JVM_25", first)
            self.assertIn("targetCompatibility = JavaVersion.VERSION_17", first)
            props = (android / "gradle.properties").read_text()
            self.assertEqual(props.count("android.builtInKotlin=false"), 1)
            self.assertEqual(props.count("android.newDsl=false"), 1)

    def test_missing_target(self):
        self.check_template("")

    def test_wrong_target(self):
        self.check_template(
            "\nkotlin {\n    compilerOptions {\n"
            "        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_25)\n"
            "    }\n}\n"
        )


if __name__ == "__main__":
    unittest.main()
