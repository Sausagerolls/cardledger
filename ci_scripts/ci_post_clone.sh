#!/bin/sh
# Xcode Cloud post-clone step.
# The Xcode project is generated from project.yml by XcodeGen and is not committed,
# so regenerate it on the runner before Xcode Cloud builds the scheme.
set -e

echo "Installing XcodeGen…"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew install xcodegen

echo "Generating Xcode project from project.yml…"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "Done. Generated CardLedger.xcodeproj"
