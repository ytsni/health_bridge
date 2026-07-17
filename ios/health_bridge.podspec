#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'health_bridge'
  s.version          = '1.0.0'
  s.summary          = 'Wrapper for Apple\'s HealthKit on iOS and Google\'s Health Connect on Android.'
  s.description      = <<-DESC
Wrapper for Apple's HealthKit on iOS and Google's Health Connect on Android.
                       DESC
  s.homepage         = 'https://github.com/ytsni/health_bridge'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Michael Ryan' => 'michael@ryan.gg' }
  s.source           = { :path => '.' }
  s.source_files = [
    'health_bridge/Sources/health/**/*.swift',
    'health_bridge/HealthBridgeWorkoutCore/Sources/HealthBridgeWorkoutCore/**/*.swift'
  ]
  s.dependency 'Flutter'
  s.frameworks = 'HealthKit'

  s.ios.deployment_target = '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.0'
end
