#ifndef AVC_STRING_H
#define AVC_STRING_H
#include "_avc.h"
#include <strings.h> /* glibc and Darwin declare strcasecmp here too */
AVC_BEGIN
/* compiler_rt */
void *memcpy(void *, const void *, size_t);
void *memmove(void *, const void *, size_t);
void *memset(void *, int, size_t);
int memcmp(const void *, const void *, size_t);
size_t strlen(const char *);
/* src/libc.zig */
void *memchr(const void *, int, size_t) AVC_SYM(memchr);
char *strchr(const char *, int) AVC_SYM(strchr);
char *strrchr(const char *, int) AVC_SYM(strrchr);
char *strstr(const char *, const char *) AVC_SYM(strstr);
int strcmp(const char *, const char *) AVC_SYM(strcmp);
int strncmp(const char *, const char *, size_t) AVC_SYM(strncmp);
char *strcpy(char *, const char *) AVC_SYM(strcpy);
char *strncpy(char *, const char *, size_t) AVC_SYM(strncpy);
char *strcat(char *, const char *) AVC_SYM(strcat);
char *strncat(char *, const char *, size_t) AVC_SYM(strncat);
char *strerror(int) AVC_SYM(strerror);
AVC_END
#endif
