#ifndef AVC_UNISTD_H
#define AVC_UNISTD_H
#include "_avc.h"
/* All fail with ENOSYS; getpid returns 0. */
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
AVC_BEGIN
pid_t getpid(void) AVC_SYM(getpid);
ssize_t read(int, void *, size_t) AVC_SYM(read);
ssize_t write(int, const void *, size_t) AVC_SYM(write);
int close(int) AVC_SYM(close);
off_t lseek(int, off_t, int) AVC_SYM(lseek);
int unlink(const char *) AVC_SYM(unlink);
ssize_t readlink(const char *, char *, size_t) AVC_SYM(readlink);
int chown(const char *, uid_t, gid_t) AVC_SYM(chown);
int isatty(int) AVC_SYM(isatty);
AVC_END
#endif
