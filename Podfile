# MobileVLCKit for iOS — used by [VLCUI](https://github.com/LePips/VLCUI)
# macOS VLCKit.xcframework is vendored under Frameworks/ (see Docs/VLCUI.md)
platform :ios, '16.0'

target 'EclipsePlexClient' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6.0'
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

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
    end
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.xcconfigs.each do |config_name, _|
      scope_xcconfig_to_ios(aggregate_target.xcconfig_path(config_name))
    end
  end
end
