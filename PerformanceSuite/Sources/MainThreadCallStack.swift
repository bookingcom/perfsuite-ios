//
//  MainThreadCallStack.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 30/06/2022.
//

// We support only arm64 for simplicity, as for other architectures there are some different types should be used.
#if arch(arm64)

import MachO
import UIKit

// In SwiftPM we create a sub-package,
// in CocoaPods we compile everything in one single target.
#if canImport(MainThreadCallStack)
import MainThreadCallStack
#endif

    /// Class is used to access main thread stack trace from a background thread.
    /// We can access `Thread.callStackSymbols` only from the thread itself, to access another thread's stack we need a bit of C-magic.
    ///
    /// I used those projects as inspiration:
    /// - https://github.com/woshiccm/RCBacktrace
    /// - https://github.com/microsoft/plcrashreporter
    /// - https://github.com/bestswifter/BSBacktraceLoggerclass
    ///
    /// We cannot write the whole logic in Swift, because to read call stack we pause the main thread.
    /// Swift runtime can obtain a lot of locks, so if main thread did acquire some lock before we paused it,
    /// we will be getting a dead lock. To avoid that the part of stack reading process is implemented in C.
    ///
    /// Logic here is simplified a bit:
    /// - support only arm64 architecture
    /// - do not print whole stack with address and offset, but only symbol and file name
    public class MainThreadCallStack {

        /// We need to call this method from the main thread before any call of `readStack`.
        static func storeMainThread() {
            if !Thread.isMainThread {
                preconditionFailure("You should call storeMainThread() from the main thread only")
            }
            mainThreadMachPortLock.lock()
            defer { mainThreadMachPortLock.unlock() }

            mainThreadMachPort = mach_thread_self()
        }
        private static var mainThreadMachPortLock = NSLock()
        private static var mainThreadMachPort: mach_port_t?

        /// Returns string representation of main thread call stack.
        /// Shouldn't be called from the main thread.
        public static func readStack() throws -> String {
            precondition(!Thread.isMainThread, "readStack() should be called from a background thread only.")

            mainThreadMachPortLock.lock()
            defer { mainThreadMachPortLock.unlock() }

            guard let mainThreadMachPort = mainThreadMachPort else {
                throw StackError.noMachPort
            }

            let frames = try readThreadState(mainThreadMachPort: mainThreadMachPort)
            let stack = frames.enumerated().compactMap { (index, frame) in
                StackItem(index: index, frame: frame)?.description
            }
            let value = stack.joined(separator: "\n")
            return value
        }

        private static func readThreadState(mainThreadMachPort: mach_port_t) throws -> [uintptr_t] {
            // call out C-function to read thread state, it pauses and resumes the main thread during the execution
            let result = read_thread_state(mainThreadMachPort)
            defer {
                if let frames = result.frames {
                    frames.deallocate()
                }
            }

            if result.size == 0 {
                throw StackError.cannotReadStack
            }

            guard let frames = result.frames else {
                throw StackError.cannotReadStack
            }

            let swiftFrames = Array(UnsafeBufferPointer(start: frames, count: Int(result.size)))
            return swiftFrames
        }
    }

    // this demangle function is not in a public header of stdlib, so need to export it
    @_silgen_name("swift_demangle")
    private
        func _stdlib_demangleImpl(
            mangledName: UnsafePointer<CChar>?,
            mangledNameLength: UInt,
            outputBuffer: UnsafeMutablePointer<CChar>?,
            outputBufferSize: UnsafeMutablePointer<UInt>?,
            flags: UInt32
        ) -> UnsafeMutablePointer<CChar>?

    private func demangle(_ name: String) -> String {
        return name.utf8CString.withUnsafeBufferPointer { namePointer in
            guard
                let resultPointer = _stdlib_demangleImpl(
                    mangledName: namePointer.baseAddress,
                    mangledNameLength: UInt(name.utf8CString.count - 1),
                    outputBuffer: nil,
                    outputBufferSize: nil,
                    flags: 0)
            else {
                return name
            }

            defer {
                resultPointer.deallocate()
            }

            if let result = String(validatingUTF8: resultPointer) {
                return result
            } else {
                return name
            }
        }
    }

    private enum StackError: Error {
        case noMachPort
        case cannotReadStack
    }

    private struct StackItem {
        let index: Int
        let frame: UInt
        let symbol: String
        let path: String
        let offset: Int

        private init(index: Int, frame: UInt, path: String, symbol: String, offset: Int) {
            self.index = index
            self.frame = frame
            self.path = path
            self.symbol = symbol
            self.offset = offset
        }

        init?(index: Int, frame: UInt) {
            var info = dl_info()
            dladdr(UnsafeRawPointer(bitPattern: frame), &info)
            if info.dli_fname == nil {
                return nil
            }
            self.init(
                index: index,
                frame: frame,
                path: Self.path(info: info),
                symbol: Self.symbol(info: info),
                offset: Self.offset(info: info, frame: frame))
        }

        private static func path(info: dl_info) -> String {
            if let fnamePointer = info.dli_fname, let fname = String(validatingUTF8: fnamePointer) {
                return (fname as NSString).lastPathComponent
            } else {
                return unknownKeyword
            }
        }

        private static func symbol(info: dl_info) -> String {
            #if DEBUG
                if info.dli_saddr != nil, let snamePointer = info.dli_sname, let sname = String(validatingUTF8: snamePointer) {
                    // if we have symbol name - put it
                    return demangle(sname)
                } else if let fbase = info.dli_fbase {
                    // otherwise we return load address of the file
                    return String(format: "0x%016llx", UInt(bitPattern: fbase))
                } else {
                    return unknownKeyword
                }
            #else
                if let fbase = info.dli_fbase {
                    // in Release we do not search for symbols because even if something is there - there is most probably some garbage, not the real symbol
                    return String(format: "0x%016llx", UInt(bitPattern: fbase))
                } else {
                    return unknownKeyword
                }
            #endif
        }

        private static func offset(info: dl_info, frame: UInt) -> Int {
            if let saddr = info.dli_saddr, let snamePointer = info.dli_sname, String(validatingUTF8: snamePointer) != nil {
                return Int(exactly: frame - UInt(bitPattern: saddr)) ?? 0
            } else if let fbase = info.dli_fbase {
                return Int(exactly: frame - UInt(bitPattern: fbase)) ?? 0
            } else {
                return 0
            }
        }

        var description: String {
            let pathPadded = path.padding(toLength: 30, withPad: " ", startingAt: 0)
            return String(format: "%-4ld%@ 0x%016llx %@ + %ld", index, pathPadded, frame, symbol, offset)
        }
    }

#endif

let unknownKeyword = "--unknown--"
