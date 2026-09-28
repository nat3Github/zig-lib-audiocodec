#ifndef AVC_FCNTL_H
#define AVC_FCNTL_H
#include "_avc.h"
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_BINARY 0
#define O_CLOEXEC 02000000
AVC_BEGIN
int open(const char *, int, ...) AVC_SYM(open);
AVC_END
#endif
