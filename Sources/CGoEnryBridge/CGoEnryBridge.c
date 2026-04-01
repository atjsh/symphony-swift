#include "CGoEnryBridge.h"
#include "enry.h"

bool SymphonyGoEnryIsBinary(const unsigned char *bytes, size_t length) {
    return IsBinary((char *)bytes, (int)length) != 0;
}

bool SymphonyGoEnryIsConfiguration(const char *path) {
    return IsConfiguration((char *)path) != 0;
}

bool SymphonyGoEnryIsDocumentation(const char *path) {
    return IsDocumentation((char *)path) != 0;
}

bool SymphonyGoEnryIsDotFile(const char *path) {
    return IsDotFile((char *)path) != 0;
}

bool SymphonyGoEnryIsImage(const char *path) {
    return IsImage((char *)path) != 0;
}

bool SymphonyGoEnryIsVendor(const char *path) {
    return IsVendor((char *)path) != 0;
}

bool SymphonyGoEnryIsGenerated(const char *path, const unsigned char *bytes, size_t length) {
    return IsGenerated((char *)path, (char *)bytes, (int)length) != 0;
}

bool SymphonyGoEnryIsTest(const char *path) {
    return IsTest((char *)path) != 0;
}

char *SymphonyGoEnryGetLanguage(const char *path, const unsigned char *bytes, size_t length) {
    return GetLanguage((char *)path, (char *)bytes, (int)length);
}

char *SymphonyGoEnryGetLanguageType(const char *language) {
    return GetLanguageType((char *)language);
}

void SymphonyGoEnryFreeCString(char *value) {
    if (value != NULL) {
        FreeCString(value);
    }
}
