workspace 'Project'
project 'Project'
deployment_target = '14.0'
install! 'cocoapods', integrate_targets: true

target :Project
platform :ios, deployment_target
use_frameworks!
pod 'PerformanceSuite', :path  => '.', :appspecs => ['PerformanceApp'], :testspecs => ['Tests', 'UITests']
pod 'SwiftLint'

post_install do |installer|
    installer.pods_project.targets.each do |target|
        if target.name == 'GCDWebServer' or target.name == 'SwiftLint' then
            target.build_configurations.each do |config|
               config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
            end
        end

        if target.name.start_with? "GCDWebServer"
            target.build_configurations.each do |config|
                config.build_settings['CLANG_WARN_STRICT_PROTOTYPES'] = 'NO' 
            end
        end
    end
end