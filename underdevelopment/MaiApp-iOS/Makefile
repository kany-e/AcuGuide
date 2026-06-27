# Convenience wrapper so the project is reproducible from the CLI.
#   make project  -> regenerate AcuGuide.xcodeproj from project.yml
#   make build    -> build for a generic iOS device (no signing)
#   make test     -> run the unit-test target on a simulator

.PHONY: project build test

project:
	xcodegen generate

build: project
	xcodebuild -scheme AcuGuide -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO build

test: project
	xcodebuild -scheme AcuGuide \
		-destination 'platform=iOS Simulator,name=iPhone 17' test
