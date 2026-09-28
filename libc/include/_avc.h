/* Shared by the libc replacement headers. Functions not provided by compiler_rt are declared
   with AVC_SYM(name): the linker symbol becomes avc_<name> (exported by src/libc.zig), so it
   never clashes with a real libc linked into the same program. */
#ifndef AVC_H
#define AVC_H

#define AVC_STR2(x) #x
#define AVC_STR(x) AVC_STR2(x)
#define AVC_SYM(n) __asm__(AVC_STR(__USER_LABEL_PREFIX__) "avc_" #n)

#ifdef __cplusplus
#define AVC_BEGIN extern "C" {
#define AVC_END }
#else
#define AVC_BEGIN
#define AVC_END
#endif

#define __need_size_t
#define __need_NULL
#define __need_wchar_t
#include <stddef.h>

typedef long long off_t;
typedef long long time_t;
typedef __INTPTR_TYPE__ ssize_t;
typedef int pid_t;
typedef unsigned int mode_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;

#endif
