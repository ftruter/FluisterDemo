#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'FluisterDemo.xcodeproj')

FileUtils.rm_rf(PROJECT_PATH) if ARGV.include?('--force')

project = Xcodeproj::Project.new(PROJECT_PATH)

project.build_configurations.each do |config|
  config.build_settings['SDKROOT'] = 'macosx'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  config.build_settings['LOCALIZATION_PREFERS_STRING_CATALOGS'] = 'YES'
  if config.name == 'Debug'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
    config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
  else
    config.build_settings['SWIFT_COMPILATION_MODE'] = 'wholemodule'
  end
end

target = project.new_target(:application, 'FluisterDemo', :osx, '14.0')
tests = project.new_target(:unit_test_bundle, 'FluisterDemoTests', :osx, '14.0')
tests.add_dependency(target)

def apply_common(config)
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
  config.build_settings['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
  config.build_settings['SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY'] = 'YES'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = ENV['DEVELOPMENT_TEAM'] || ''
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '1.0'
  config.build_settings['COMBINE_HIDPI_IMAGES'] = 'YES'
end

target.build_configurations.each do |config|
  apply_common(config)
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'truter.com.fluister.demo'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Fluister'
  config.build_settings['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.utilities'
  config.build_settings['INFOPLIST_KEY_NSMicrophoneUsageDescription'] =
    'Fluister listens on this Mac to transcribe Afrikaans and South African English on-device.'
  config.build_settings['INFOPLIST_KEY_NSHumanReadableCopyright'] = 'Copyright © 2026 Fluister contributors'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'FluisterDemo/FluisterDemo.entitlements'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  config.build_settings['ENABLE_PREVIEWS'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
  config.build_settings['ENABLE_TESTABILITY'] = 'YES' if config.name == 'Debug'
end

tests.build_configurations.each do |config|
  apply_common(config)
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'truter.com.fluister.demo.tests'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/FluisterDemo.app/Contents/MacOS/FluisterDemo'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks']
end

sources = project.main_group.new_group('FluisterDemo', 'FluisterDemo')
Dir.chdir(File.join(ROOT, 'FluisterDemo')) do
  Dir.glob('*.swift').sort.each do |name|
    ref = sources.new_file(name)
    target.source_build_phase.add_file_reference(ref)
  end
  sources.new_file('FluisterDemo.entitlements')
  loc = sources.new_file('Localizable.xcstrings')
  assets = sources.new_file('Assets.xcassets')
  icon = sources.new_file('AppIcon.icon')
  icon.last_known_file_type = 'folder.iconcomposer.icon'
  target.add_resources([assets, loc, icon])
end

test_group = project.main_group.new_group('FluisterDemoTests', 'FluisterDemoTests')
Dir.chdir(File.join(ROOT, 'FluisterDemoTests')) do
  Dir.glob('*.swift').sort.each do |name|
    ref = test_group.new_file(name)
    tests.source_build_phase.add_file_reference(ref)
  end
end

pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = 'https://github.com/argmaxinc/WhisperKit.git'
pkg.requirement = {
  'kind' => 'upToNextMajorVersion',
  'minimumVersion' => '0.9.0'
}
project.root_object.package_references << pkg

dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.product_name = 'WhisperKit'
dep.package = pkg
target.package_product_dependencies << dep
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = dep
target.frameworks_build_phase.files << build_file

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(tests)
scheme.set_launch_target(target)
scheme.save_as(PROJECT_PATH, 'FluisterDemo', true)

puts "Wrote #{PROJECT_PATH}"
puts "scheme FluisterDemo"
