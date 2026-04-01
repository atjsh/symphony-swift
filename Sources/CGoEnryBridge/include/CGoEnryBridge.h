#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

bool SymphonyGoEnryIsBinary(const unsigned char *bytes, size_t length);
bool SymphonyGoEnryIsConfiguration(const char *path);
bool SymphonyGoEnryIsDocumentation(const char *path);
bool SymphonyGoEnryIsDotFile(const char *path);
bool SymphonyGoEnryIsImage(const char *path);
bool SymphonyGoEnryIsVendor(const char *path);
bool SymphonyGoEnryIsGenerated(const char *path, const unsigned char *bytes, size_t length);
bool SymphonyGoEnryIsTest(const char *path);
char *SymphonyGoEnryGetLanguage(const char *path, const unsigned char *bytes, size_t length);
char *SymphonyGoEnryGetLanguageType(const char *language);
void SymphonyGoEnryFreeCString(char *value);

#ifdef __cplusplus
}
#endif
