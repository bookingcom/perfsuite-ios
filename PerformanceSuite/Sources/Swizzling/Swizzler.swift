//
//  Swizzler.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 05/07/2021.
//


import Foundation
import ObjectiveC.runtime

private func makeSwizzledSelector(_ selector: Selector) -> Selector {
    return NSSelectorFromString(swizzledSelectorPrefix + NSStringFromSelector(selector))
}
private let swizzledSelectorPrefix = "performance_suite__"

public enum SwizzlerError: Error, LocalizedError {
    case methodNotFound(class: NSObject.Type, selector: Selector)
    case swizzledSecondTime(class: NSObject.Type, selector: Selector)
    case unswizzleNotSwizzled(class: NSObject.Type, selector: Selector)

    public var errorDescription: String? {
        switch self {
        case let .methodNotFound(class: cls, selector: selector):
            return "No method \(selector) found in class \(cls)."
        case let .swizzledSecondTime(class: cls, selector: selector):
            return "You are trying to swizzle method \(selector) in class \(cls) that was already swizzled. You should unswizzle before that."
        case let .unswizzleNotSwizzled(class: cls, selector: selector):
            return "You are trying to unswizzle method \(selector) in class \(cls) that wasn't swizzled."
        }
    }
}


/// Container for static swizzle and unswizzle methods
public enum Swizzler {

    /// Adds calling of `action` block before/after every call of `selector` method in class `class`.
    ///
    /// It is done by injection another method and swizzling existing method with the new one.
    ///
    /// NB! it will work only for @objc methods marked with `dynamic` keyword.
    ///
    /// Will crash if you call it on non-existing `selector` in `class`.
    ///
    /// Supports only methods with maximum 2 parameters.
    ///
    /// - Parameters:
    ///   - classToSwizzle: which class to patch
    ///   - selector: which method to patch
    ///   - after: determines if `action` is called before or after the original method
    ///   - action: what action to call before the method is called
    public static func swizzle<T: NSObject>(class classToSwizzle: T.Type, selector: Selector, after: Bool = false, action: @escaping (T) -> Void) throws {
        let swizzledSelector = makeSwizzledSelector(selector)

        guard let method = class_getInstanceMethod(classToSwizzle, selector),
              let oldImp = class_getMethodImplementation(classToSwizzle, selector)
        else {
            throw SwizzlerError.methodNotFound(class: classToSwizzle, selector: selector)
        }

        if isSwizzled(class: classToSwizzle, selector: selector) == true {
            throw SwizzlerError.swizzledSecondTime(class: classToSwizzle, selector: selector)
        }

        let types = method_getTypeEncoding(method)

        let block: @convention(block) (NSObject, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> UnsafeMutableRawPointer = { (sself, p1, p2) in
            guard let sself = sself as? T else {
                // we can't throw error from here, but this shouldn't happen, so just do a fatalError
                fatalError("Expected \(T.self) but got object \(sself).")
            }
            if !after {
                action(sself)
            }
            guard let oldImp = class_getMethodImplementation(classToSwizzle, swizzledSelector) else {
                // we can't throw error from here, but this shouldn't happen, so just do a fatalError
                fatalError("Something went wrong. There is no existing method for selector \(swizzledSelector) in class \(classToSwizzle)")
            }
            let oldImpFunction = unsafeBitCast(
                oldImp,
                to: (@convention(c) (NSObject, Selector, UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> UnsafeMutableRawPointer).self)
            let result = oldImpFunction(sself, swizzledSelector, p1, p2)
            if after {
                action(sself)
            }
            return result
        }

        let imp = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))

        class_replaceMethod(classToSwizzle, selector, imp, types)
        class_addMethod(classToSwizzle, swizzledSelector, oldImp, types)

        markSwizzled(true, class: classToSwizzle, selector: selector)
    }


    /// Reverts changes that were applied by `swizzle` method.
    ///
    /// Will crash if called on the method that wasn't swizzled.
    /// - Parameters:
    ///   - classToSwizzle: which class to revert
    ///   - selector: which method to revert
    public static func unswizzle(class classToSwizzle: NSObject.Type, selector: Selector) throws {
        let swizzledSelector = makeSwizzledSelector(selector)

        if isSwizzled(class: classToSwizzle, selector: selector) == false {
            throw SwizzlerError.unswizzleNotSwizzled(class: classToSwizzle, selector: selector)
        }

        guard let imp = class_getMethodImplementation(classToSwizzle, selector) else {
            throw SwizzlerError.methodNotFound(class: classToSwizzle, selector: selector)
        }

        guard let oldMethod = class_getInstanceMethod(classToSwizzle, swizzledSelector),
              let oldImp = class_getMethodImplementation(classToSwizzle, swizzledSelector)
        else {
            throw SwizzlerError.unswizzleNotSwizzled(class: classToSwizzle, selector: selector)
        }

        imp_removeBlock(imp)

        let types = method_getTypeEncoding(oldMethod)
        class_replaceMethod(classToSwizzle, selector, oldImp, types)

        markSwizzled(false, class: classToSwizzle, selector: selector)
    }

    private static func isSwizzled(class classToSwizzle: NSObject.Type, selector: Selector) -> Bool {
        let key = NSStringFromClass(classToSwizzle)
        swizzledMethodsLock.lock()
        let set = swizzledMethods[key]
        let result = set?.contains(selector) == true
        swizzledMethodsLock.unlock()
        return result
    }

    private static func markSwizzled(_ swizzled: Bool, class classToSwizzle: NSObject.Type, selector: Selector) {
        let key = NSStringFromClass(classToSwizzle)
        swizzledMethodsLock.lock()
        if swizzled {
            if swizzledMethods[key] != nil {
                swizzledMethods[key]?.insert(selector)
            } else {
                swizzledMethods[key] = [selector]
            }
        } else {
            swizzledMethods[key]?.remove(selector)
        }

        swizzledMethodsLock.unlock()
    }

    private static var swizzledMethods: [String: Set<Selector>] = [:]
    private static let swizzledMethodsLock = NSLock()
}
