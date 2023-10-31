Pod::Spec.new do |s|
  s.name                 = 'PerformanceSuite'
  s.version              = '1.2.0'
  s.summary              = 'Performance monitoring library for iOS'
  s.homepage             = 'https://github.com/bookingcom/perfsuite-ios' 
  s.license              = { :type => 'MIT', :file => 'LICENSE' }
  s.author               = { 'Gleb Tarasov' => 'gleb.tarasov@booking.com' }
  s.source               = { :git => 'https://github.com/bookingcom/perfsuite-ios.git', :tag => s.version.to_s }
  s.source_files         = 'PerformanceSuite/Sources/**/*.swift', 'PerformanceSuite/MainThreadCallStack/**/*.{h,c}'  
  s.public_header_files = 'PerformanceSuite/MainThreadCallStack/include/*.h'
  s.platform             = :ios, "14.0"
  s.swift_version        = "5.7.1"

  s.test_spec 'Tests' do |test_spec|
    test_spec.requires_app_host = true
    test_spec.source_files = 'PerformanceSuite/Tests/*.swift'
  end
end
