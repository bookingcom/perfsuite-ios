 ![Tests](https://github.com/bookingcom/perfsuite-ios/actions/workflows/tests.yml/badge.svg)
 ![CodeQL](https://github.com/bookingcom/perfsuite-ios/actions/workflows/codeql.yml/badge.svg)
 ![Cocoapods](https://img.shields.io/cocoapods/l/PerformanceSuite)
 ![Cocoapods](https://img.shields.io/cocoapods/v/PerformanceSuite)
 ![Cocoapods platforms](https://img.shields.io/cocoapods/p/PerformanceSuite)
 ![Code Coverage](https://raw.githubusercontent.com/bookingcom/perfsuite-ios/badges/.badges/main/code_coverage.svg)

![PerformanceSuite_logo_small](https://github.com/bookingcom/perfsuite-ios/assets/983021/384c8786-c7ee-40cf-a46a-ee7ee656e814)


# PerformanceSuite

PerformanceSuite is an iOS Swift library designed to measure and collect performance and quality metrics of iOS applications. 

Compared to other solutions like MetricKit, Firebase Performance, Instabug, Sentry, etc., it offers additional flexibility. However, it focuses on the native part of performance monitoring. For storing and visualizing your metrics, building monitoring graphs, and setting up alerts, you will need to have your own backend.

This library is used in the [main Booking.com iOS app](https://apps.apple.com/app/booking-com-hotels-travel/id367003839) which is used by millions of users every day. We've described how we measure performance at Booking.com in [this article](https://medium.com/booking-com-development/measuring-mobile-apps-performance-in-production-726e7e84072f).

We've also opened the code for the similar [Android PerformanceSuite](https://github.com/bookingcom/perfsuite-android).

## Pros

- Performance events are delivered in real-time directly to your code, allowing for comprehensive analysis.
- You can monitor performance within your A/B tests.
- You have the flexibility to build any real-time performance charts with custom alerting.


## Cons

- A custom backend is needed to collect the metrics, display the graphs and setup alerting. 

## Supported features

- [TTI](https://github.com/bookingcom/perfsuite-ios/wiki/TTI) (Time to Interactive) monitoring for screens.
- [Freeze time](https://github.com/bookingcom/perfsuite-ios/wiki/Freeze-Time) rendering performance monitoring for screens.
- Overall app freeze time monitoring.
- [Startup time](https://github.com/bookingcom/perfsuite-ios/wiki/Startup-Time) monitoring.
- Fatal and non-fatal [hangs](https://github.com/bookingcom/perfsuite-ios/wiki/Hangs) with the stack trace.
- Watchdog [terminations](https://github.com/bookingcom/perfsuite-ios/wiki/Watchdog-Terminations) (memory or CPU terminations).
- Logging of all UIKit controller events for easier debugging.

#### Check our [Wiki](https://github.com/bookingcom/perfsuite-ios/wiki) for more details.

Please note that PerformanceSuite currently does not support the tracking of standard crashes. You will need an additional tool to collect stack traces for crashes (for example, Firebase Crashlytics).

## How it works

`PerformanceSuite` monitoring should be activated as your application launches, by supplying an object that is set up to process the performance metrics. As your application continues to run, you'll receive callbacks that deliver these metrics.

```swift

func startupTimeReceived(_ data: StartupTimeData) { ... }

func fatalHangReceived(info: HangInfo) { ... }

func nonFatalHangReceived(info: HangInfo) { ... }

func viewControllerLeakReceived(viewController: UIViewController) { ... }

func watchdogTerminationReceived(_ data: WatchdogTerminationData) { ... }

func appRenderingMetricsReceived(metrics: RenderingMetrics) { ... }

```

For screen-level metrics you should return `ScreenIdentifier` from `screenIdentifier(for:)` or nil if this view controller shouldn't be tracked. Check [Screen identifiers] for the example.

```swift

func screenIdentifier(for viewController: UIViewController) -> ScreenIdentifier? { ... }

func ttiMetricsReceived(metrics: TTIMetrics, screen: ScreenIdentifier) { ... }

func renderingMetricsReceived(metrics: RenderingMetrics, screen: ScreenIdentifier) { ... }

```


## SwiftUI support

PerformanceSuite screen tracking heavily relies on the UIKit UIViewController's lifecycle.

For purely SwiftUI apps, iOS still creates `UINavigationController` under the hood to perform navigations, and these cases are supported by PerformanceSuite.

However, custom SwiftUI transitions that do not create any `UIHostingController` under the hood are not currently automated. For now you can use [Fragment TTI tracking](https://github.com/bookingcom/perfsuite-ios/wiki/TTI#fragments-tti-tracking) for such cases. We may introduce some syntax sugar later if there is a demand for that.

For most apps, though, the current setup is good enough to automatically track screen openings with SwiftUI views inside `UIHostingController`. Check [Usage](README.md#usage) section for the details.

## Installation

#### Swift Package Manager
- In Xcode, select File > Add Packages.
- Enter https://github.com/bookingcom/perfsuite-ios in the "Search or Enter Package URL" dialog.
- In the next page select "Up to Next Major" and specify the latest version.
- On the final page, choose the `PerformanceSuite` library and add it to your target.
- Your package dependency will be added to your .xcodeproj file.

#### CocoaPods
To integrate `PerformanceSuite` into your Xcode project using CocoaPods, specify it in your Podfile:

```
pod 'PerformanceSuite'
```

Currently CocoaPods repo [has problems](https://github.com/CocoaPods/cocoapods.org/issues/424) with indexing the new added pods, that's why if it doesn't work you may specify the source url and tag

```
pod 'PerformanceSuite', :git => 'https://github.com/bookingcom/perfsuite-ios.git', :tag => '0.0.4' # use the last released version here
```

## Usage

To receive performance events, you must have a class implementing some of the following protocols:
- `TTIMetricsReceiver`
- `RenderingMetricsReceiver` 
- `AppRenderingMetricsReceiver`
- `WatchDogTerminationsReceiver`
- `HangsReceiver`
- `ViewControllerLeaksReceiver` 
- `StartupTimeReceiver`
- `ViewControllerLoggingReceiver`
- `FragmentTTIMetricsReceiver`

Alternatively, you can use the `PerformanceSuiteMetricsReceiver` to receive all events.

Performance monitoring should be initiated as early as possible in your app. For instance, you could begin at the start of the `application(application:didFinishLaunchingWithOptions:)` method.

```swift
let metricsConsumer = MetricsConsumer()
try PerformanceMonitoring.enable(config: .all(receiver: metricsConsumer))

// or with more flexibility

let metricsConsumer = MetricsConsumer()
let config: Config = [
    .screenLevelTTI(metricsConsumer),
    .screenLevelRendering(metricsConsumer),
    .appLevelRendering(metricsConsumer),
    .hangs(metricsConsumer),
]
try PerformanceMonitoring.enable(
    config: config,
    // you may pass your own key-value storage
    storage: KeyValueStorage.default,
    // you may pass a flag if app did crash from Crashlytics
    didCrashPreviously: didCrashPreviously
)

```

### Screen identifiers

All screen-level metrics are coming from PerformanceSuite to your code with the `UIViewController` object. To convert view controller object to a `ScreenIdentifier` you may use such approach:

- Define `PerformanceScreen` enum with screen identifiers for all your screens
- Define protocol `PerformanceTrackableScreen` where every screen should return this enum
- Add SwiftUI support for `UIHostingController` if needed

```swift

// We define enum with all our possible screens
// If you have too many screens, there can be several enums, 
// or just a string identifier.
enum PerformanceScreen: String {
    case search
    case details
    case checkout
}

// We define a protocol for screens to conform
protocol PerformanceTrackableScreen {
    var performanceScreen: PerformanceScreen? { get }
}

// For view controllers it is easy, we just return which screen is this
extension SearchViewController: PerformanceTrackableScreen {
    var performanceScreen: PerformanceScreen? { .search  }
}

// If you have SwiftUI screens without corresponding custom `UIHostingController`, 
// you will need to add introspection logic to find root views 
// in any `UIHostingController` in the app.
//
// We should conform to this protocol in the topmost view of the screen.
//
// NB: if possible, better to use your own subclass for `UIHostingController`
// and implement `PerformanceTrackableScreen` only in your subclass.
// Otherwise it may be additional performance overhead to introspect 
// all hosting controllers in the app
extension CheckoutScreenSwiftUIView: PerformanceTrackableScreen {
    var performanceScreen: PerformanceScreen? { .checkout }
}

// We also need to implement the protocol in UIHostingController,
// So we can determine which is the SwiftUI view inside this controller.
extension UIHostingController: PerformanceTrackableScreen {
    var performanceScreen: PerformanceScreen? {
        return (introspectRootView() as? PerformanceTrackableScreen)?.performanceScreen
    }
}

// In our metrics consumer we will receive UIViewController 
// and should determine which screen is this.
class MetricsConsumer: TTIMetricsReceiver {
    func screenIdentifier(for viewController: UIViewController) -> PerformanceScreen? {
        (viewController as? PerformanceTrackableScreen)?.performanceScreen
    }

    func ttiMetricsReceived(metrics: TTIMetrics, screen: PerformanceScreen) {
        // send the event to your backend with this identifier
        send(metric: "tti", value: metrics.tti.seconds, screen: performanceScreen.rawValue)
    }
}

```

## How to reproduce metrics?

In the repository we have the sample app `PerformanceApp`, on the first screen there are options to generate all the possible metrics:

<img width="513" alt="menu" src="https://github.com/bookingcom/perfsuite-ios/assets/983021/268375e2-5b2d-433b-9741-dad5091f9698">

- Startup time is generated on a `PerformanceApp` launch
- Freeze time and App Freeze time will be generated after you open *Freeze time* screen
- For other metrics select corresponding menu option

We use this `PerformanceApp` in the integration UI tests, to verify all the metrics are properly generated.

## Development

To launch project locally:
- install CocoaPods with `gem install cocoapods`
- generate `Pods` folder with `pod install`
- open `Project.xcworkspace` to launch sample `PerformanceApp` or run tests
- Use `PerformanceApp` scheme to launch the app
- Use `UnitTests` to launch unit tests
- Use `UITests` to launch integration UI tests. Note, that this scheme is compiling in Release mode.

# ACKNOWLEDGMENT
This software was originally developed at Booking.com. With approval from Booking.com, this software was released as open source, for which the authors would like to express their gratitude.
