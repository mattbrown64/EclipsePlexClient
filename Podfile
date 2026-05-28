# MobileVLCKit for iOS — used by [VLCUI](https://github.com/LePips/VLCUI)
# macOS VLCKit.xcframework is vendored under Frameworks/ (see Docs/VLCUI.md)
platform :ios, '26.0'

target 'EclipsePlexClient' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.7.0'

  target 'EclipsePlexClientTests' do
    inherit! :search_paths
  end

  target 'EclipsePlexClientUITests' do
    inherit! :search_paths
  end
end

def scope_xcconfig_to_ios(xcconfig_path)
  xcconfig = File.read(xcconfig_path)
  %w[OTHER_LDFLAGS FRAMEWORK_SEARCH_PATHS OTHER_MODULE_VERIFIER_FLAGS].each do |key|
    match = xcconfig.match(/^#{key} = (.+)$/)
    next unless match

    value = match[1]
    xcconfig.gsub!(/^#{key} = .+\n/, '')
    xcconfig << "\n#{key}[sdk=iphoneos*] = #{value}\n"
    xcconfig << "#{key}[sdk=iphonesimulator*] = #{value}\n"
  end
  File.write(xcconfig_path, xcconfig)
end

UIKIT_VLC_SCRIPT_GUARD = <<~'SH'
  if [[ "${PLATFORM_NAME}" != "iphoneos" && "${PLATFORM_NAME}" != "iphonesimulator" && "${PLATFORM_NAME}" != "appletvos" && "${PLATFORM_NAME}" != "appletvsimulator" ]]; then
    exit 0
  fi
SH

def limit_pods_scripts_to_ios(installer)
  installer.aggregate_targets.each do |aggregate_target|
    user_project = aggregate_target.user_project
    user_project.native_targets.each do |target|
      next unless target.name == 'EclipsePlexClient'

      target.shell_script_build_phases.each do |phase|
        next unless phase.name&.start_with?('[CP]')

        next if phase.shell_script&.include?('PLATFORM_NAME')

        phase.shell_script = UIKIT_VLC_SCRIPT_GUARD + phase.shell_script.to_s
      end
    end
    user_project.save
  end
end

def inject_ios_vlckit_search_paths(installer)
  slice_sim = '$(PROJECT_DIR)/Pods/MobileVLCKit/MobileVLCKit.xcframework/ios-arm64_i386_x86_64-simulator'
  slice_device = '$(PROJECT_DIR)/Pods/MobileVLCKit/MobileVLCKit.xcframework/ios-arm64_armv7_armv7s'

  installer.aggregate_targets.each do |aggregate_target|
    user_project = aggregate_target.user_project
    user_project.native_targets.each do |target|
      next unless %w[EclipsePlexClient EclipsePlexClientTests EclipsePlexClientUITests].include?(target.name)

      target.build_configurations.each do |config|
        config.build_settings['FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]'] ||= '$(inherited)'
        config.build_settings['FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]'] ||= '$(inherited)'
        config.build_settings['FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]'] = [
          '$(inherited)', slice_sim,
          '$(PODS_CONFIGURATION_BUILD_DIR)/XCFrameworkIntermediates/MobileVLCKit'
        ]
        config.build_settings['FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]'] = [
          '$(inherited)', slice_device,
          '$(PODS_CONFIGURATION_BUILD_DIR)/XCFrameworkIntermediates/MobileVLCKit'
        ]
      end
    end
    user_project.save
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
      config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator appletvos appletvsimulator'
    end
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.xcconfigs.each do |config_name, _|
      scope_xcconfig_to_ios(aggregate_target.xcconfig_path(config_name))
    end
  end
end

post_integrate do |installer|
  remove_pods_umbrella_framework(installer)
  limit_pods_scripts_to_ios(installer)
  inject_ios_vlckit_search_paths(installer)
  add_mobilevlckit_prepare_phase(installer)
end

def add_mobilevlckit_prepare_phase(installer)
  installer.aggregate_targets.each do |aggregate_target|
    user_project = aggregate_target.user_project
    user_project.native_targets.each do |target|
      next unless target.name == 'EclipsePlexClient'

      existing = target.shell_script_build_phases.find { |p| p.name == 'Prepare MobileVLCKit (iOS)' }
      existing&.remove_from_project

      phase = target.new_shell_script_build_phase('Prepare MobileVLCKit (iOS)')
      phase.shell_script = <<~SCRIPT
        if [[ "${PLATFORM_NAME}" != "iphoneos" && "${PLATFORM_NAME}" != "iphonesimulator" && "${PLATFORM_NAME}" != "appletvos" && "${PLATFORM_NAME}" != "appletvsimulator" ]]; then
          exit 0
        fi
        "${SRCROOT}/scripts/prepare-mobilevlckit-ios.sh"
      SCRIPT
      phase.show_env_vars_in_log = '0'

      # Run before compile / embed.
      target.build_phases.move(phase, 0)
    end
    user_project.save
  end
end

def remove_pods_umbrella_framework(installer)
  installer.aggregate_targets.each do |aggregate_target|
    user_project = aggregate_target.user_project
    user_project.native_targets.each do |target|
      next unless %w[EclipsePlexClient EclipsePlexClientTests EclipsePlexClientUITests].include?(target.name)

      target.frameworks_build_phase.files.to_a.each do |build_file|
        name = build_file.file_ref&.path || build_file.display_name || ''
        next unless name.include?('Pods_EclipsePlexClient')

        build_file.remove_from_project
      end
    end
    user_project.save
  end
end
