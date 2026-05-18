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

## OpenTelemetry Integration

`PerformanceSuiteOTel` is an additional library that bridges `PerformanceSuite` metrics to the [OpenTelemetry](https://opentelemetry.io) pipeline — most signals as spans, view-controller leaks as log records — so you can route performance data through any OTel-compatible backend (Embrace, Honeycomb, an in-house OTLP collector, …) without writing a custom bridge. It depends on `PerformanceSuite` and on [`opentelemetry-swift-core`](https://github.com/open-telemetry/opentelemetry-swift-core)'s `OpenTelemetryApi`; it does not pull in the OTel SDK.

### Installation

#### Swift Package Manager

Add `PerformanceSuiteOTel` as a target dependency alongside `PerformanceSuite`. The package URL is the same one you already use:

```
https://github.com/bookingcom/perfsuite-ios
```

#### CocoaPods

```
pod 'PerformanceSuite/OTel'
```

The `OTel` subspec depends on `OpenTelemetry-Swift-Api` (the CocoaPods spec name; the imported Swift module name is `OpenTelemetryApi`).

### Standalone usage

`OTelInstrumenter<Screen, Fragment>` conforms to all eight `PerformanceSuite` receiver protocols and can be passed wherever the library expects a receiver. The simplest setup uses it as the only receiver:

```swift
import PerformanceSuite
import PerformanceSuiteOTel

let otel = OTelInstrumenter<PerformanceScreen, PerformanceFragment>()

let config: Config = [
    .startupTime(otel),
    .screenLevelTTI(otel),
    .screenLevelRendering(otel),
    .appLevelRendering(otel),
    .hangs(otel),
    .watchdogTerminations(otel),
    .fragmentTTI(otel),
    .viewControllerLeaks(otel),
]
try PerformanceMonitoring.enable(config: config)
```

### Combining OTel with custom receivers

If you already have a custom receiver (e.g. an analytics pipeline) and want to fan signals out to both that receiver and OTel, wrap each one in the matching `Multi*Receiver` from `PerformanceSuite` core:

```swift
let otel = OTelInstrumenter<PerformanceScreen, PerformanceFragment>()
let custom = MyCustomReceiver()
let screenId: (UIViewController) -> PerformanceScreen? = { vc in
    (vc as? PerformanceTrackableScreen)?.performanceScreen
}

let config: Config = [
    .startupTime(MultiStartupTimeReceiver(receivers: [custom, otel])),
    .screenLevelTTI(MultiTTIMetricsReceiver(
        screenIdentifier: screenId,
        receivers: [custom, otel]
    )),
    .hangs(MultiHangsReceiver(receivers: [custom, otel])),
    .viewControllerLeaks(
        [custom, otel],
        shouldTrack: { viewController in
            // Chain-wide opt-out: returning false short-circuits the
            // observer's dispatch entirely, so neither the custom receiver
            // nor OTel sees an excluded view controller. Use this to keep
            // squeak-style and OTel emissions in lockstep.
            !(viewController is UINavigationController)
        }
    ),
    // ...
]
```

The `viewControllerLeaks(_:shouldTrack:)` convenience wraps `MultiViewControllerLeaksReceiver`, whose optional `shouldTrack` predicate gates dispatch for *all* children at once. The predicate is invoked once per leak, immediately before any child receiver is called; returning `false` skips the dispatch so the chain stays in lockstep.

> **iOS 16+ for the three generic Multi receivers.** `MultiTTIMetricsReceiver`, `MultiRenderingMetricsReceiver`, and `MultiFragmentTTIMetricsReceiver` store `[any P<X>]` arrays, whose runtime support shipped with iOS 16 (SE-0353). They are gated with `@available(iOS 16.0, *)`. The other five `Multi*Receiver` types (including `MultiViewControllerLeaksReceiver`) and all of `OTelInstrumenter` work on iOS 15+.

### View-controller leak log records

`OTelInstrumenter` emits view-controller leaks as **OTel log records** rather than spans — leak detection is a point-in-time event with no meaningful duration, and a log with `severity = WARN` and `body = "view_controller_leak"` is the right semantic shape. The record carries:

| Attribute | Value |
| --- | --- |
| `vc.class_name` | `String(describing: type(of: viewController))`. For `UIHostingController`s (anything conforming to `RootViewIntrospectable`), the introspected SwiftUI root view's type is used instead, so the record carries the meaningful user-facing type rather than the generic-mangled `UIHostingController<…>`. |
| `vc.identifier` | `viewController.description` (the standard `NSObject` `<MyClass: 0x…>` form). |
| `app.startup.prewarmed` | `true` if the app was started by iOS pre-warming, otherwise `false`. Mirrors the startup span's policy. |

Records are emitted via `OpenTelemetry.instance.loggerProvider`, lazily resolved at first emission (see [Provider resolution](#provider-resolution) below).

### Host attribute enrichment

`OTelInstrumenter.init` accepts an optional `attributeProvider:` closure that is invoked **once per emission** with the matching `PerformanceSuiteSignalContext`. The dictionary it returns is merged onto the resulting span (or log record) — useful for adding host-app context (experiment buckets, low-power-mode, …) that the SDK itself doesn't know about.

```swift
let otel = OTelInstrumenter<PerformanceScreen, PerformanceFragment>(
    spanNamePrefix: "myapp",
    attributeProvider: { context in
        // Exhaustive switch — the compiler will flag any future signal
        // kind, so enrichment stays complete by construction.
        switch context {
        case .watchdogTermination, .fatalHang:
            // Use cross-launch state — the previous session's experiments,
            // for example.
            return previousSessionExperimentBuckets()
        case .nonFatalHang, .viewControllerLeak:
            // In-session events; current-session state is appropriate.
            return currentSessionExperimentBuckets()
        case .startup, .appRendering:
            return ["app.low_power_mode": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled)]
        case .screenTTI, .screenRendering, .fragmentTTI:
            return [:]
        }
    }
)
```

`PerformanceSuiteSignalContext` is a hybrid enum: hang / watchdog / leak cases carry the SDK's own public payload type directly (`HangInfo`, `WatchdogTerminationData`, `UIViewController`); TTI / rendering / startup cases carry small generic-erased projection structs (`ScreenContext`, `FragmentContext`, `StartupContext`, `AppRenderingContext`). Pattern-bind the payload on the cases that have one — for example `case .fatalHang(let info):` exposes every public field of `HangInfo` (`callStack`, `duration`, `appRuntimeInfo`, …) without requiring an upstream PR to widen a curated projection.

Splitting fatal and non-fatal hang dispatch into distinct enum cases makes the emitter pick the right one at construction time — mis-threading fatality is a compile-time error rather than a silent default. Host enrichment closures get the same guarantee through exhaustive switches.

**SDK-set keys are protected.** Each per-signal merge filters host attributes against the universe of attribute keys the SDK reserves for that signal (`OTelSDKKeys.startup`, `OTelSDKKeys.hang`, `OTelSDKKeys.viewControllerLeak`, …). A host attribute matching one of those keys is silently dropped at the merge boundary, so semantic-convention values like `screen.tti.ms`, `app.state`, `hang.duration.ms`, or `vc.class_name` can never be overwritten by host code.

### Provider resolution

By default, `OTelInstrumenter` resolves both `OpenTelemetry.instance.tracerProvider` and `OpenTelemetry.instance.loggerProvider` lazily — at every emission, not at instantiation. This is intentional: the host app's OTel SDK (Embrace, vendor SDK, …) typically registers the global providers during its own startup, which may run *after* `PerformanceMonitoring.enable(...)`. Resolving lazily means signals emitted before the SDK is ready fall through to the no-op default providers (silently dropped, no crash), and every emission afterward uses the real providers.

You can also inject explicit providers at construction time — useful for tests, multi-tenant setups, or routing PerformanceSuite signals to a different tracer / logger than the rest of the app:

```swift
let otel = OTelInstrumenter<PerformanceScreen, PerformanceFragment>(
    tracerProvider: customTracerProvider,
    loggerProvider: customLoggerProvider,
    instrumentationName: "perfsuite-ios",        // default, included on every span / log record
    instrumentationVersion: "1.7.0"              // optional
)
```

### Semantic conventions

Span names, log bodies, and attribute keys are exposed as constants on `OTelSemanticConventions` (e.g. `OTelSemanticConventions.SpanName.appStartup`, `OTelSemanticConventions.Attribute.screenTTIMs`, `OTelSemanticConventions.LogBody.viewControllerLeak`). Backend dashboards can target these without grepping the source. The full list:

- **Span names**: `app-startup`, `screen-tti.<name>`, `fragment-tti.<name>`, `screen-rendering.<name>`, `app-rendering`, `app-hang`, `app-watchdog-termination`.
- **Log bodies**: `view_controller_leak`.
- **Span attributes**: startup timing, screen / fragment TTI, rendering frame counts and freeze time, hang type / duration / top screen, watchdog termination state and memory.
- **Log attributes** (view-controller leaks): `vc.class_name`, `vc.identifier`, `app.startup.prewarmed`.

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
