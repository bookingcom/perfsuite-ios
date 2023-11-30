#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/utils.h>
#include <dlfcn.h>
#include <libgen.h>
#include <stdio.h>
#include "MainThreadCallStack.h"

// We support only arm64 for simplicity, as for other architectures there are some different types should be used.
#if defined(__aarch64__)

#define MAX_STACK_SIZE 1024

typedef struct frame {
    struct frame *previous_frame;
    uintptr_t return_address;
} Frame;

static size_t read_frames(uint64_t bit_pattern, uintptr_t *frames) {
    size_t frames_count = 0;

    if (bit_pattern == 0) {
        return frames_count;
    }
    
    Frame *frame_pointer = (Frame*)bit_pattern;
    if (!frame_pointer) {
        return frames_count;
    }

    Frame frame = *frame_pointer;
    
    while (1) {
        // We take only lower bits from the return address, higher bits of 64bit number may contain garbage
        // in Release mode, which I'm not sure where is coming from.
        // I suspect it might be connected to pointer authentication, but I have no proofs
        // https://developer.apple.com/documentation/security/preparing_your_app_to_work_with_pointer_authentication
        // For example, raw value can be 0x8b5d1b0105b0b1d8, but actually should be 0x0000000105b0b1d8,
        // or 0x572a6b8102e75668 instead of 0x0000000102e75668.
        // To tackle this we add mask to the address. Mask value I picked up after testing, it may be covering not all the cases.
        uintptr_t address = frame.return_address & 0x7ffffffff;
        if (address == 0 || !frame.previous_frame) {
            break;
        } else {
            frame = *frame.previous_frame;
        }

        if (frames_count < MAX_STACK_SIZE) {
            frames[frames_count++] = address;
        } else {
            break;
        }
    }
    
    return frames_count;
}

thread_state_result read_thread_state(mach_port_t main_thread_mach_port) {
   
    uintptr_t *result = malloc(sizeof(uintptr_t) * MAX_STACK_SIZE);
    
    arm_thread_state64_t thread_state;
    mach_msg_type_number_t state_count = ARM_THREAD_STATE64_COUNT;
    
    // To read stack trace we should pause the thread before reading
    if (thread_suspend(main_thread_mach_port) != KERN_SUCCESS) {
        return (thread_state_result){ 0, result };
    }
    
    kern_return_t kr = thread_get_state(main_thread_mach_port, ARM_THREAD_STATE64, (thread_state_t)&thread_state, &state_count);
    if (kr != KERN_SUCCESS) {
        thread_resume(main_thread_mach_port);
        return (thread_state_result){ 0, result };
    }

    uintptr_t pc = thread_state.__pc;  // Program counter
    uintptr_t lr = thread_state.__lr;  // Link register

    if (pc == 0 || lr == 0) {
        thread_resume(main_thread_mach_port);
        return (thread_state_result){ 0, result };
    }

    result[0] = pc;
    result[1] = lr;

    size_t result_length = 2;

    uintptr_t *frames_pointer = result + result_length; // Pointer to the part of result where frames will be stored

    size_t frames_length = read_frames(thread_state.__fp, frames_pointer);
    
    // we can resume main thread from here
    thread_resume(main_thread_mach_port);

    result_length += frames_length;
    return (thread_state_result){ result_length, result };
}

#endif

extern const char *macho_arch_name_for_mach_header_reexported(void) __API_AVAILABLE(ios(16.0)) {
    // if we call macho_arch_name_for_mach_header_reexported(NULL), it will return arm64 even for devices with arm64e,
    // because the main binary is compiled for arm64. But to symbolicate stack traces with the system frameworks,
    // we want to know if the device is arm64e, that's why we are passing mach_header for some system framework.
    // We assume that the framework at index 0 is always a system one.
    const struct mach_header *mh = _dyld_get_image_header(0);
    return macho_arch_name_for_mach_header(mh);
}
