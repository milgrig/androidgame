#!/usr/bin/env python3
"""
Comprehensive QA Test Runner with Bug Documentation

This script runs the comprehensive test suite and automatically
documents any bugs found in a structured format.

Usage:
    python run_comprehensive_qa.py                    # Run all tests
    python run_comprehensive_qa.py --level 01         # Run specific level
    python run_comprehensive_qa.py --quick           # Run quick smoke test
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path


class QATestRunner:
    """Runs comprehensive QA tests and documents results."""

    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.test_file = self.project_root / "tests/agent/test_all_levels_comprehensive.py"
        self.report_file = self.project_root / "tests/agent/T021_QA_REPORT.md"
        self.bugs_file = self.project_root / "tests/agent/T021_BUGS.json"
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "total": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "errors": 0,
            "bugs": []
        }

    def run_tests(self, level: str = None, verbose: bool = True):
        """Run the test suite."""
        cmd = ["pytest", str(self.test_file), "-v", "--tb=short"]

        if level:
            test_class = f"TestLevel{level.zfill(2)}"
            cmd.append(f"-k={test_class}")

        if verbose:
            cmd.append("-s")

        print(f"{'═' * 60}")
        print(f"Running Comprehensive QA Tests")
        print(f"{'═' * 60}")
        print(f"Command: {' '.join(cmd)}")
        print(f"{'═' * 60}\n")

        try:
            result = subprocess.run(
                cmd,
                cwd=self.project_root,
                capture_output=True,
                text=True,
                timeout=600  # 10 minutes max
            )

            self.parse_results(result.stdout, result.stderr)
            self.print_summary()

            if result.returncode != 0:
                print(f"\n⚠️  Tests failed with exit code {result.returncode}")
                self.extract_bugs(result.stdout)
            else:
                print(f"\n✅ All tests passed!")

            return result.returncode

        except subprocess.TimeoutExpired:
            print("\n❌ Tests timed out after 10 minutes")
            return 1
        except Exception as e:
            print(f"\n❌ Error running tests: {e}")
            return 1

    def parse_results(self, stdout: str, stderr: str):
        """Parse pytest output to extract results."""
        lines = stdout.split('\n')

        for line in lines:
            # Look for pytest summary line
            if " passed" in line or " failed" in line:
                parts = line.split()
                for i, part in enumerate(parts):
                    if "passed" in part and i > 0:
                        try:
                            self.results["passed"] = int(parts[i-1])
                        except ValueError:
                            pass
                    elif "failed" in part and i > 0:
                        try:
                            self.results["failed"] = int(parts[i-1])
                        except ValueError:
                            pass
                    elif "skipped" in part and i > 0:
                        try:
                            self.results["skipped"] = int(parts[i-1])
                        except ValueError:
                            pass
                    elif "error" in part and i > 0:
                        try:
                            self.results["errors"] = int(parts[i-1])
                        except ValueError:
                            pass

        self.results["total"] = (
            self.results["passed"] +
            self.results["failed"] +
            self.results["skipped"] +
            self.results["errors"]
        )

    def extract_bugs(self, output: str):
        """Extract bug information from test failures."""
        lines = output.split('\n')
        current_test = None
        current_failure = []
        in_failure = False

        for line in lines:
            # Detect test start
            if "FAILED" in line or "ERROR" in line:
                # Extract test name
                if "::" in line:
                    parts = line.split("::")
                    if len(parts) >= 3:
                        current_test = {
                            "test_class": parts[1],
                            "test_method": parts[2].split()[0],
                            "level": parts[1].replace("TestLevel", ""),
                            "failure_output": []
                        }
                in_failure = True
            elif in_failure:
                if line.strip().startswith("____") or line.strip().startswith("===="):
                    # End of failure block
                    if current_test:
                        current_test["failure_output"] = "\n".join(current_failure)
                        self.results["bugs"].append(current_test)
                        current_test = None
                        current_failure = []
                    in_failure = False
                else:
                    current_failure.append(line)

        # Save bugs to JSON
        if self.results["bugs"]:
            with open(self.bugs_file, 'w') as f:
                json.dump(self.results, f, indent=2)
            print(f"\n📝 Bug report saved to: {self.bugs_file}")

    def print_summary(self):
        """Print test results summary."""
        print(f"\n{'═' * 60}")
        print(f"TEST RESULTS SUMMARY")
        print(f"{'═' * 60}")
        print(f"Total Tests:    {self.results['total']}")
        print(f"✅ Passed:      {self.results['passed']}")
        print(f"❌ Failed:      {self.results['failed']}")
        print(f"⏭️  Skipped:     {self.results['skipped']}")
        print(f"💥 Errors:      {self.results['errors']}")
        print(f"{'═' * 60}")

        if self.results["bugs"]:
            print(f"\n🐛 BUGS FOUND: {len(self.results['bugs'])}")
            print(f"{'─' * 60}")
            for bug in self.results["bugs"]:
                print(f"  • Level {bug['level']}: {bug['test_method']}")
            print(f"{'─' * 60}")

    def update_report(self):
        """Update the QA report with test results."""
        if not self.report_file.exists():
            print(f"⚠️  Report file not found: {self.report_file}")
            return

        report = self.report_file.read_text()

        # Update summary section
        summary = f"""
### Summary
- **Total Tests:** {self.results['total']}
- **Passed:** {self.results['passed']}
- **Failed:** {self.results['failed']}
- **Skipped:** {self.results['skipped']}
- **Bugs Found:** {len(self.results['bugs'])}
- **Test Date:** {self.results['timestamp']}
"""

        # Replace placeholder summary
        if "### Summary" in report:
            parts = report.split("### Summary")
            before = parts[0]
            after = parts[1].split("### Bugs Found", 1)
            if len(after) > 1:
                report = before + "### Summary" + summary + "\n### Bugs Found" + after[1]
            else:
                report = before + "### Summary" + summary

        self.report_file.write_text(report)
        print(f"\n📄 Report updated: {self.report_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Run comprehensive QA tests for The Symmetry Vaults"
    )
    parser.add_argument(
        "--level",
        type=str,
        help="Test specific level only (e.g., '01', '12')"
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Quick smoke test (Level 01 only)"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        default=True,
        help="Verbose output (default: True)"
    )
    parser.add_argument(
        "--update-report",
        action="store_true",
        help="Update the QA report with results"
    )

    args = parser.parse_args()

    # Determine project root (3 levels up from this script)
    project_root = Path(__file__).resolve().parents[2]

    runner = QATestRunner(project_root)

    # Quick mode: only test Level 01
    if args.quick:
        args.level = "01"
        print("🚀 Quick smoke test mode: Testing Level 01 only\n")

    # Run tests
    exit_code = runner.run_tests(level=args.level, verbose=args.verbose)

    # Update report if requested
    if args.update_report:
        runner.update_report()

    # Print instructions
    if exit_code == 0:
        print("\n✨ All tests passed! The game is working correctly.")
    else:
        print("\n🔍 Some tests failed. Check the bug report for details:")
        print(f"   {runner.bugs_file}")
        print("\nTo investigate failures:")
        print(f"   cat {runner.bugs_file} | jq")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
