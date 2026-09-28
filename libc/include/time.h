#ifndef AVC_TIME_H
#define AVC_TIME_H
#include "_avc.h"
/* No clock: time() and clock_gettime() fail (-1), clock() returns -1. */
typedef long clock_t;
typedef int clockid_t;
#define CLOCKS_PER_SEC 1000000L
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
struct timespec { time_t tv_sec; long tv_nsec; };
struct tm { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; };
AVC_BEGIN
time_t time(time_t *) AVC_SYM(time);
clock_t clock(void) AVC_SYM(clock);
int clock_gettime(clockid_t, struct timespec *) AVC_SYM(clock_gettime);
AVC_END
#endif
