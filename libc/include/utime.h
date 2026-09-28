#ifndef AVC_UTIME_H
#define AVC_UTIME_H
#include "_avc.h"
struct utimbuf { time_t actime; time_t modtime; };
AVC_BEGIN
int utime(const char *, const struct utimbuf *) AVC_SYM(utime);
AVC_END
#endif
