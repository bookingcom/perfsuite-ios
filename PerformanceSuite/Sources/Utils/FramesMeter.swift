//
//  FramesMeter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import QuartzCore
import UIKit

protocol FramesMeterReceiver: AnyObject {

    /// Method is called to report actual frame duration
    /// - Parameters:
    ///   - frameDuration: Time between the current frame and the previous frame
    ///   - refreshRateDuration: Minimal time between frames if everything is rendered without delays
    func frameTicked(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval)
}

protocol FramesMeter {
    func subscribe(receiver: FramesMeterReceiver)
    func unsubscribe(receiver: FramesMeterReceiver)
}

/// CADisplayLink holds the strong reference to it's target,
/// To break strong reference cycle, we create a proxy object, which won't hold
/// strong reference to `DefaultFramesMeter`.
private class DisplayLinkProxy {
    init(displayLinkUpdatedAction: @escaping () -> Void) {
        self.displayLinkUpdatedAction = displayLinkUpdatedAction
    }
    private let displayLinkUpdatedAction: () -> Void

    @objc func displayLinkUpdated() {
        displayLinkUpdatedAction()
    }
}

final class DefaultFramesMeter: FramesMeter {

    init(appStateListener: AppStateListener = DefaultAppStateListener()) {
        self.appStateListener = appStateListener
        appStateListener.didChange = { [weak self] in
            self?.updateState()
        }
    }

    private lazy var displayLink: CADisplayLink = {
        let proxy = DisplayLinkProxy { [weak self] in
            self?.displayLinkUpdated()
        }
        let displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.displayLinkUpdated))
        displayLink.add(to: .main, forMode: .common)
        displayLink.isPaused = true
        return displayLink
    }()

    private var previousTimestamp: CFTimeInterval?
    private var previousDuration: CFTimeInterval?

    // can't use FramesMeterReceiver as a generic type parameter here, so let's live with AnyObject
    private var receivers = NSHashTable<AnyObject>.weakObjects()

    private let appStateListener: AppStateListener

    func subscribe(receiver: FramesMeterReceiver) {
        PerformanceMonitoring.queue.async {
            self.receivers.add(receiver)
            self.updateState()
        }
    }

    func unsubscribe(receiver: FramesMeterReceiver) {
        PerformanceMonitoring.queue.async {
            self.receivers.remove(receiver)
            self.updateState()
        }
    }

    private func updateState() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))

        // NSHashTable doesn't have `isEmpty`, ignore swiftlint
        // swiftlint:disable:next empty_count
        let hasReceivers = (receivers.count > 0)
        let isInBackground = appStateListener.isInBackground
        // this property is thread safe in CADisplayLink, we can access it from our queue
        let isPaused = displayLink.isPaused
        let shouldBePaused = isInBackground || !hasReceivers

        if !isPaused && shouldBePaused {
            displayLink.isPaused = true
        }
        if isPaused && !shouldBePaused {
            previousTimestamp = nil
            displayLink.isPaused = false
        }
    }

    private func displayLinkUpdated() {
        // timestamp of the current frame
        let timestamp = self.displayLink.timestamp
        // expected timestamp of the next frame
        let targetTimestamp = self.displayLink.targetTimestamp
        // ideal duration coming from display link is not always equal to `targetTimestamp - timestamp`
        let displayLinkDuration = self.displayLink.duration
        PerformanceMonitoring.queue.async {
            if self.appStateListener.isInBackground {
                // in case app went to background during our `async` call, just do nothing
                return
            }
            if let previousTimestamp = self.previousTimestamp {
                let previousDuration = self.previousDuration ?? 0
                var actualFrameDuration = timestamp - previousTimestamp
                let targetFrameDuration = targetTimestamp - timestamp

                // For dynamic FPS feature on iPhone 13 Pro/Pro Plus frames duration is often too long just after FPS is changing,
                // but this is not visible to the user and Apple doesn't consider this as a hitch in Instruments.
                // So we also are trying to reduce such fake dropped frames in our report with these checks,
                // by ignoring those frame when duration is changing.
                let fpsIsChanging =
                    notEqual(previousDuration, displayLinkDuration) || notEqual(targetFrameDuration, displayLinkDuration)
                // From my testing on iPhone 13 Pro duration of those fake dropped frames is always no more than 1 frame,
                // so if we lost more than 1 frame, we should count those dropped frames too, because it is not the fake, but the real degradation.
                let noMoreThan1DroppedFrame =
                    (actualFrameDuration < 2 * targetFrameDuration + RenderingMetrics.refreshRateDurationThreshold)
                if fpsIsChanging && noMoreThan1DroppedFrame {
                    actualFrameDuration = targetFrameDuration
                }
                self.receivers.allObjects.forEach {
                    ($0 as? FramesMeterReceiver)?.frameTicked(
                        frameDuration: actualFrameDuration, refreshRateDuration: targetFrameDuration)
                }
                self.previousDuration = displayLinkDuration
            }
            self.previousTimestamp = timestamp
        }
    }

    deinit {
        self.displayLink.invalidate()
    }
}

private func notEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    return abs(lhs - rhs) < RenderingMetrics.refreshRateDurationThreshold
}
