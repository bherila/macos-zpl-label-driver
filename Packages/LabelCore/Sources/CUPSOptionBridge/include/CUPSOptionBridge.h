#ifndef LABEL_CUPS_OPTION_BRIDGE_H
#define LABEL_CUPS_OPTION_BRIDGE_H

#include <stddef.h>

// Returns 1 when NAME is present, 0 when absent, and -1 for malformed input
// or a value that cannot fit in OUTPUT. OUTPUT is NUL-terminated on success.
int label_cups_option_value(const char *options, const char *name, char *output, size_t output_size);

#endif
