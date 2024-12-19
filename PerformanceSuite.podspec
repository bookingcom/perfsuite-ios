Pod::Spec.new do |s|
  s.name                 = 'PerformanceSuite'
  s.version              = '1.5.0'
  s.summary              = 'Performance monitoring library for iOS'
  s.homepage             = 'https://github.com/bookingcom/perfsuite-ios' 
  s.license              = { :type => 'MIT', :file => 'LICENSE' }
  s.author               = { 'Gleb Tarasov' => 'gleb.tarasov@booking.com' }
  s.source               = { :git => 'https://github.com/bookingcom/perfsuite-ios.git', :tag => s.version.to_s }
  s.platform             = :ios, '14.0'
  s.swift_version        = '5.7.1'
  s.default_subspec      = 'Core'

  s.subspec 'Core' do |core_spec|
    core_spec.source_files = 'PerformanceSuite/Sources/**/*.swift', 'PerformanceSuite/MainThreadCallStack/**/*.{h,c}'  
    core_spec.public_header_files = 'PerformanceSuite/MainThreadCallStack/include/*.h'
  end

  s.subspec 'Crashlytics' do |cr_spec|
    cr_spec.source_files = 'PerformanceSuite/Crashlytics/Sources/*.swift', 'PerformanceSuite/Crashlytics/Imports/include/*.h'  
    cr_spec.public_header_files = 'PerformanceSuite/Crashlytics/Imports/include/*.h'
    cr_spec.dependency 'PerformanceSuite/Core'
    cr_spec.dependency 'FirebaseCrashlytics'
  end

  # Sample App which is also used for UI tests as a host
  s.app_spec 'PerformanceApp' do |app_spec|
    app_spec.source_files = 'PerformanceSuite/PerformanceApp/**/*.swift'
    app_spec.dependency 'GCDWebServer'
    app_spec.dependency 'PerformanceSuite/Crashlytics'
  end

  # Unit tests
  s.test_spec 'Tests' do |test_spec|
    test_spec.requires_app_host = true
    test_spec.source_files = 'PerformanceSuite/Tests/**/*.swift'
    test_spec.dependency 'PerformanceSuite/Crashlytics'
  end

  # UI Tests
  s.test_spec 'UITests' do |test_spec|
    test_spec.requires_app_host = true
    test_spec.test_type = :ui
    test_spec.source_files = 'PerformanceSuite/UITests/**/*.swift', 'PerformanceSuite/PerformanceApp/UITestsInterop.swift'
    test_spec.app_host_name = 'PerformanceSuite/PerformanceApp'
    test_spec.dependency 'PerformanceSuite/PerformanceApp'
    test_spec.dependency 'GCDWebServer'
  end
end
