deployment_target = '14.0'
platform :ios, deployment_target

target 'PerformanceApp'
pod 'PerformanceSuite', :path => '.', :testspecs => ['Tests'] 
pod 'SwiftLint'

post_install do |installer|
 installer.pods_project.targets.each do |target|
  if target.name == 'SwiftLint' then
	target.build_configurations.each do |config|
	 config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
	end
  end
 end
end