#if defined(__aarch64__)

#include <mach/mach_types.h>

typedef struct {
    size_t size;
    uintptr_t *frames;
} thread_state_result;

thread_state_result read_thread_state(mach_port_t thread);

#endif

#include <Availability.h>
// I couldn't call this function from swift, not sure why, that's why I'm re-exporting it here
extern const char *macho_arch_name_for_mach_header_reexported(void) __API_AVAILABLE(ios(16.0));
