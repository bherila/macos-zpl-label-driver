#include "CUPSOptionBridge.h"
#include <cups/cups.h>
#include <string.h>

int label_cups_option_value(const char *options, const char *name, char *output, size_t output_size) {
  if (!options || !name || !output || output_size == 0) return -1;
  cups_option_t *parsed = NULL;
  int count = cupsParseOptions(options, 0, &parsed);
  const char *value = cupsGetOption(name, count, parsed);
  if (!value) {
    cupsFreeOptions(count, parsed);
    return 0;
  }
  size_t length = strlen(value);
  if (length >= output_size) {
    cupsFreeOptions(count, parsed);
    return -1;
  }
  memcpy(output, value, length + 1);
  cupsFreeOptions(count, parsed);
  return 1;
}
