workspace 'Project'
project 'Project'
deployment_target = '14.0'
install! 'cocoapods', integrate_targets: false, share_schemes_for_development_pods: true

platform :ios, deployment_target
use_frameworks!
pod 'PerformanceSuite', :path  => '.', :appspecs => ['PerformanceApp'], :testspecs => ['Tests', 'UITests']
pod 'SwiftLint'

post_install do |installer|
 installer.pods_project.targets.each do |target|
  if target.name == 'GCDWebServer' then
  target.build_configurations.each do |config|
   config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
  end
  end
 end
end