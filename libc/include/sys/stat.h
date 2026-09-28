#ifndef AVC_SYS_STAT_H
#define AVC_SYS_STAT_H
#include "../_avc.h"
/* All fail with ENOSYS. */
struct stat { mode_t st_mode; uid_t st_uid; gid_t st_gid; off_t st_size; time_t st_atime; time_t st_mtime; };
#define S_IFMT 0170000
#define S_IFDIR 0040000
#define S_IFREG 0100000
#define S_IFLNK 0120000
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
#define S_IRUSR 0400
#define S_IWUSR 0200
#define S_IXUSR 0100
#define S_IRWXU 0700
#define S_IRGRP 040
#define S_IWGRP 020
#define S_IROTH 04
#define S_IWOTH 02
AVC_BEGIN
int stat(const char *, struct stat *) AVC_SYM(stat);
int lstat(const char *, struct stat *) AVC_SYM(stat);
int fstat(int, struct stat *) AVC_SYM(fstat);
int chmod(const char *, mode_t) AVC_SYM(chmod);
AVC_END
#endif
