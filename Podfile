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
        target.build_configurations.each do |config|
           config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
           config.build_settings['EMBEDDED_CONTENT_CONTAINS_SWIFT'] = nil
           config.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = nil
           config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        end
        
        if target.name == 'FirebaseCrashlytics' then
            target.build_configurations.each do |config|
                config.build_settings['OTHER_LDFLAGS'] = "-Xlinker -no_warn_duplicate_libraries #{config.build_settings['OTHER_LDFLAGS']}"
            end
        end

        if target.name == 'GCDWebServer' then
            target.build_configurations.each do |config|
                config.build_settings['CLANG_WARN_STRICT_PROTOTYPES'] = 'NO' 
            end
        end
    end
end