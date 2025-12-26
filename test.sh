#!/bin/bash

# Run tests with code coverage
swift test --enable-code-coverage

# Generate HTML coverage report (only for MediaBrowser codebase)
xcrun llvm-cov show --ignore-filename-regex=".build/|Tests/|checkouts/" --instr-profile=.build/debug/codecov/default.profdata --format=html .build/debug/MediaBrowserPackageTests.xctest/Contents/MacOS/MediaBrowserPackageTests > coverage.html

echo "Coverage report generated: coverage.html"