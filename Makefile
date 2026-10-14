# Jonwork build automation

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

ROOT_DIR := $(abspath $(CURDIR))
WORKSPACE := $(ROOT_DIR)/Jonwork.xcworkspace
IOS_SCHEME := Jonwork
EXTENSION_SCHEME := JonworkTranslationProvider
CONFIGURATION ?= Debug
TEST_DESTINATION ?=
TEST_ONLY ?=
XCODEBUILD_EXTRA ?=
ARCHIVE_PATH ?= $(ROOT_DIR)/BuildArtifacts/Jonwork-unsigned.xcarchive
RESULT_BUNDLE_PATH ?=
DERIVED_DATA ?= /private/tmp/jonwork-deriveddata
BUILD_HOME := $(DERIVED_DATA)/home
XDG_CACHE_HOME := $(DERIVED_DATA)/xdg-cache
MODULE_CACHE := $(DERIVED_DATA)/ModuleCache.noindex
UNSIGNED_FLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
SIMULATOR_SIGNING_FLAGS := CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
SIGNING_FLAGS ?= $(UNSIGNED_FLAGS)

IOS_DESTINATION := generic/platform=iOS
IOS_SIMULATOR_DESTINATION := generic/platform=iOS Simulator
CATALYST_DESTINATION := generic/platform=macOS,variant=Mac Catalyst

XCODEBUILD_WRAPPER := ./Resources/DevKit/scripts/run_xcodebuild.sh
TRANSLATION_CHECK_SCRIPT := Resources/DevKit/scripts/check_untranslated.py
TRANSLATION_STALE_SCRIPT := Resources/DevKit/scripts/check_translations.py

XCODEBUILD = $(XCODEBUILD_WRAPPER) \
	-workspace "$(WORKSPACE)" \
	-configuration $(CONFIGURATION) \
	-derivedDataPath "$(DERIVED_DATA)" \
	-skipMacroValidation \
	-skipPackagePluginValidation \
	$(SIGNING_FLAGS) \
	$(XCODEBUILD_EXTRA)

LOCALIZATION_FILES := \
	Jonwork/Resources/Localizable.xcstrings \
	Jonwork/Resources/InfoPlist.xcstrings \
	JonworkTranslationProvider/Localizable.xcstrings \
	JonworkTranslationProvider/InfoPlist.xcstrings \
	JonworkWidgets/Localizable.xcstrings \
	JonworkWidgets/InfoPlist.xcstrings

ifeq ($(dirty),1)
	export ALLOW_DIRTY := 1
endif

BUILD_ENV := HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)"

define prepare-build-dirs
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
endef

define run-localization-script
	set -e; for file in $(LOCALIZATION_FILES); do \
		python3 $(1) "$$file"; \
	done
endef

.PHONY: all help \
	build build-ios build-ios-qa build-ios-candidate build-ios-simulator build-catalyst build-extension \
	test test-unit test-online-e2e test-localization-validator \
	install-metal-toolchain package-resolve package-update scan-license \
	localization-check localization-stale-check localization-extracted-check \
	archive archive-ios archive-macos \
	chore clean clean-build

all: build

help:
	@echo "Build:"
	@echo "  build                 Build the iOS and Mac Catalyst app"
	@echo "  build-ios             Build the iOS app"
	@echo "  build-ios-qa          Build the QA iOS app"
	@echo "  build-ios-candidate   Build the production-candidate iOS app"
	@echo "  build-ios-simulator   Build the iOS Simulator app"
	@echo "  build-catalyst        Build the Mac Catalyst app"
	@echo "  build-extension       Build the translation provider extension"
	@echo ""
	@echo "Test:"
	@echo "  test                  Run the default test flow"
	@echo "  test-unit             Run app tests on the first available iOS simulator"
	@echo "  test-online-e2e       Run online e2e tests"
	@echo "  test-localization-validator  Test compiler localization validation"
	@echo ""
	@echo "Packages & licenses:"
	@echo "  install-metal-toolchain  Install the Xcode Metal toolchain"
	@echo "  package-resolve       Resolve SwiftPM packages"
	@echo "  package-update        Upgrade SwiftPM packages"
	@echo "  scan-license          Refresh open source licenses"
	@echo ""
	@echo "Localization:"
	@echo "  localization-check        Check for missing translations"
	@echo "  localization-extracted-check Check changed app compiler-extracted keys"
	@echo "  localization-stale-check  Prune stale keys and verify completeness"
	@echo ""
	@echo "Archive:"
	@echo "  archive               Archive iOS and macOS release builds"
	@echo "  archive-ios           Archive the iOS release build"
	@echo "  archive-macos         Archive the macOS release build"
	@echo ""
	@echo "Release verification:"
	@echo "  appstore-check          Run local App Store readiness checks"
	@echo "  appstore-check-strict   Fail when release blockers remain"
	@echo "  archive-ios-unsigned   Build unsigned Release archive for inspection"
	@echo "  project-list           List workspace projects and schemes"
	@echo "  show-build-settings    Inspect the iOS app build settings"
	@echo ""
	@echo "Housekeeping:"
	@echo "  chore                 Run localization hygiene and license refresh"
	@echo "  clean-build           Remove repo-local build artifacts"
	@echo "  clean                 Remove repo-local build artifacts and derived data"
	@echo ""
	@echo "Flags:"
	@echo "  dirty=1               Allow flows that intentionally run on a dirty tree"

build: build-ios build-catalyst

build-ios:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-ios $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$(IOS_DESTINATION)" \
		build

build-ios-qa:
	$(MAKE) build-ios CONFIGURATION=QA

build-ios-candidate:
	$(MAKE) build-ios CONFIGURATION=ProductionCandidate

build-ios-simulator: SIGNING_FLAGS = $(SIMULATOR_SIGNING_FLAGS)
build-ios-simulator:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-ios-simulator $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$(IOS_SIMULATOR_DESTINATION)" \
		build

build-catalyst:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-catalyst $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$(CATALYST_DESTINATION)" \
		SUPPORTS_MACCATALYST=YES \
		build

build-extension:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=build-extension $(XCODEBUILD) \
		-scheme $(EXTENSION_SCHEME) \
		-destination "$(IOS_DESTINATION)" \
		build

test: test-unit

# The default test destination is a simulator. Explicit hardware/Mac targets
# retain their existing unsigned checks unless the caller supplies signing flags.
test-unit: SIGNING_FLAGS = $(if $(strip $(TEST_DESTINATION)),$(if $(findstring platform=iOS Simulator,$(TEST_DESTINATION)),$(SIMULATOR_SIGNING_FLAGS),$(UNSIGNED_FLAGS)),$(SIMULATOR_SIGNING_FLAGS))
test-unit:
	$(prepare-build-dirs)
	DESTINATION="$(TEST_DESTINATION)"; \
	if [ -z "$$DESTINATION" ]; then DESTINATION="$$(./Resources/DevKit/scripts/get_first_ios_simulator.sh)"; fi; \
	$(BUILD_ENV) XCBUILD_LABEL=test-unit $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$$DESTINATION" \
		$(foreach selected_test,$(TEST_ONLY),-only-testing:$(selected_test)) \
		test

test-online-e2e:
	./Resources/DevKit/scripts/run_online_e2e_tests.sh

install-metal-toolchain:
	./Resources/DevKit/scripts/install-metal-toolchain.sh

package-resolve:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=package-resolve $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) -resolvePackageDependencies

package-update:
	./Resources/DevKit/scripts/update-packages.sh

scan-license:
	./Resources/DevKit/scripts/scan.license.sh

localization-extracted-check:
	python3 Resources/DevKit/scripts/check_extracted_i18n.py --derived-data "$(DERIVED_DATA)" --catalog Jonwork/Resources/Localizable.xcstrings $(if $(LOCALIZATION_SOURCE_MANIFEST),--manifest "$(LOCALIZATION_SOURCE_MANIFEST)")

test-localization-validator:
	python3 Resources/DevKit/scripts/test_check_extracted_i18n.py

localization-check:
	$(call run-localization-script,$(TRANSLATION_CHECK_SCRIPT))

localization-stale-check:
	$(call run-localization-script,$(TRANSLATION_STALE_SCRIPT))

archive:
	./Resources/DevKit/scripts/archive.all.sh all

archive-ios:
	./Resources/DevKit/scripts/archive.all.sh ios

archive-macos:
	./Resources/DevKit/scripts/archive.all.sh macos

chore:
	$(MAKE) localization-stale-check
	$(MAKE) localization-check
	$(MAKE) package-resolve
	$(MAKE) scan-license dirty=1

clean-build:
	rm -rf "$(ROOT_DIR)/.build" "$(ROOT_DIR)/BuildArtifacts"

clean: clean-build
	rm -rf "$(DERIVED_DATA)"

.PHONY: appstore-check appstore-check-strict test-release-checks test-sharing-policy test-model-exchange project-list show-build-settings archive-ios-unsigned
appstore-check:
	python3 Resources/DevKit/scripts/appstore_check.py

appstore-check-strict:
	python3 Resources/DevKit/scripts/appstore_check.py --strict

test-release-checks:
	python3 Resources/DevKit/scripts/test_appstore_check.py

test-sharing-policy:
	zsh Resources/DevKit/scripts/run_sharing_policy_tests.sh

test-model-exchange:
	swift test --package-path Frameworks/JonworkModelExchange

project-list:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=project-list $(XCODEBUILD) -scheme $(IOS_SCHEME) -list

show-build-settings:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=show-build-settings $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) -destination "$(IOS_DESTINATION)" -showBuildSettings

archive-ios-unsigned: override CONFIGURATION = Release
archive-ios-unsigned:
	$(prepare-build-dirs)
	$(BUILD_ENV) XCBUILD_LABEL=archive-ios-unsigned $(XCODEBUILD) \
		-scheme $(IOS_SCHEME) \
		-destination "$(IOS_DESTINATION)" \
		-archivePath "$(ARCHIVE_PATH)" \
		$(if $(RESULT_BUNDLE_PATH),-resultBundlePath "$(RESULT_BUNDLE_PATH)",) archive
