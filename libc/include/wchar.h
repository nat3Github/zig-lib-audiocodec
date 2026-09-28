#ifndef AVC_WCHAR_H
#define AVC_WCHAR_H
#include "_avc.h"
typedef struct { unsigned int state; } mbstate_t;
AVC_BEGIN
size_t wcslen(const wchar_t *) AVC_SYM(wcslen);
size_t wcsrtombs(char *, const wchar_t **, size_t, mbstate_t *) AVC_SYM(wcsrtombs);
AVC_END
#endif
