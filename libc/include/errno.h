#ifndef AVC_ERRNO_H
#define AVC_ERRNO_H
#include "_avc.h"
AVC_BEGIN
int *avc_errno_location_(void) AVC_SYM(errno_location);
AVC_END
#define errno (*avc_errno_location_())
#define EPERM 1
#define ENOENT 2
#define EINTR 4
#define EIO 5
#define EBADF 9
#define EAGAIN 11
#define ENOMEM 12
#define EACCES 13
#define EEXIST 17
#define EINVAL 22
#define ENOSPC 28
#define ESPIPE 29
#define EDOM 33
#define ERANGE 34
#define ENOSYS 38
#define EOVERFLOW 75
#define ENOTSUP 95
#endif
