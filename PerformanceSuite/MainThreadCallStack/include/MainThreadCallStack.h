#if defined(__aarch64__)

#include <mach/mach_types.h>

typedef struct {
    size_t size;
    uintptr_t *frames;
} thread_state_result;

thread_state_result read_thread_state(mach_port_t thread);

#endif
