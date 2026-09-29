#ifndef AVC_STDLIB_H
#define AVC_STDLIB_H
#include "_avc.h"
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 0x7fffffff
#define alloca __builtin_alloca
AVC_BEGIN
/* src/c_allocator.zig: the Zig allocator of the current Decoder/Encoder call */
void *malloc(size_t) AVC_SYM(malloc);
void *calloc(size_t, size_t) AVC_SYM(calloc);
void *realloc(void *, size_t) AVC_SYM(realloc);
void free(void *) AVC_SYM(free);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *)) AVC_SYM(qsort);
double strtod(const char *, char **) AVC_SYM(strtod);
long strtol(const char *, char **, int) AVC_SYM(strtol);
unsigned long strtoul(const char *, char **, int) AVC_SYM(strtoul);
int atoi(const char *) AVC_SYM(atoi);
double atof(const char *) AVC_SYM(atof);
char *getenv(const char *) AVC_SYM(getenv);
unsigned int arc4random(void) AVC_SYM(arc4random);
__attribute__((noreturn)) void abort(void) AVC_SYM(abort);
__attribute__((noreturn)) void exit(int) AVC_SYM(exit);
static inline int abs(int x) { return x < 0 ? -x : x; }
static inline long labs(long x) { return x < 0 ? -x : x; }
static inline long long llabs(long long x) { return x < 0 ? -x : x; }
AVC_END
#endif
