#ifndef AVC_STDIO_H
#define AVC_STDIO_H
#include "_avc.h"
#include <stdarg.h>
/* No files here: every FILE function fails (fopen returns NULL, errno = ENOSYS). The libs are
   only used through their callback / memory APIs. snprintf & co. are real. */
typedef struct avc_FILE FILE;
typedef long long fpos_t;
#define EOF (-1)
#define BUFSIZ 1024
#define FILENAME_MAX 4096
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
AVC_BEGIN
extern FILE *const avc_stdin_ AVC_SYM(stdin);
extern FILE *const avc_stdout_ AVC_SYM(stdout);
extern FILE *const avc_stderr_ AVC_SYM(stderr);
#define stdin avc_stdin_
#define stdout avc_stdout_
#define stderr avc_stderr_
FILE *fopen(const char *, const char *) AVC_SYM(fopen);
FILE *fdopen(int, const char *) AVC_SYM(fdopen);
FILE *freopen(const char *, const char *, FILE *) AVC_SYM(freopen);
FILE *tmpfile(void) AVC_SYM(tmpfile);
int fclose(FILE *) AVC_SYM(fclose);
size_t fread(void *, size_t, size_t, FILE *) AVC_SYM(fread);
size_t fwrite(const void *, size_t, size_t, FILE *) AVC_SYM(fwrite);
int fseek(FILE *, long, int) AVC_SYM(fseek);
long ftell(FILE *) AVC_SYM(ftell);
int fseeko(FILE *, off_t, int) AVC_SYM(fseeko);
off_t ftello(FILE *) AVC_SYM(ftello);
/* Windows spellings (vorbisfile.h, opusfile), off_t is 64-bit everywhere here */
int fseeko64(FILE *, off_t, int) AVC_SYM(fseeko);
off_t ftello64(FILE *) AVC_SYM(ftello);
int _fseeki64(FILE *, off_t, int) AVC_SYM(fseeko);
off_t _ftelli64(FILE *) AVC_SYM(ftello);
void rewind(FILE *) AVC_SYM(rewind);
int feof(FILE *) AVC_SYM(feof);
int ferror(FILE *) AVC_SYM(ferror);
void clearerr(FILE *) AVC_SYM(clearerr);
int fflush(FILE *) AVC_SYM(fflush);
int fileno(FILE *) AVC_SYM(fileno);
int setvbuf(FILE *, char *, int, size_t) AVC_SYM(setvbuf);
int fgetc(FILE *) AVC_SYM(fgetc);
int getc(FILE *) AVC_SYM(fgetc);
int getchar(void) AVC_SYM(getchar);
int ungetc(int, FILE *) AVC_SYM(ungetc);
char *fgets(char *, int, FILE *) AVC_SYM(fgets);
int fputc(int, FILE *) AVC_SYM(fputc);
int putc(int, FILE *) AVC_SYM(fputc);
int fputs(const char *, FILE *) AVC_SYM(fputs);
int puts(const char *) AVC_SYM(puts);
int remove(const char *) AVC_SYM(remove);
int rename(const char *, const char *) AVC_SYM(rename);
void perror(const char *) AVC_SYM(perror);
/* output to FILE is discarded */
int printf(const char *, ...) AVC_SYM(printf);
int fprintf(FILE *, const char *, ...) AVC_SYM(fprintf);
int vprintf(const char *, va_list) AVC_SYM(vprintf);
int vfprintf(FILE *, const char *, va_list) AVC_SYM(vfprintf);
/* real: %% %c %s %d %i %u %x %X %p with l, ll, z, h flags, width, precision for %s */
int sprintf(char *, const char *, ...) AVC_SYM(sprintf);
int snprintf(char *, size_t, const char *, ...) AVC_SYM(snprintf);
int vsprintf(char *, const char *, va_list) AVC_SYM(vsprintf);
int vsnprintf(char *, size_t, const char *, va_list) AVC_SYM(vsnprintf);
AVC_END
#endif
