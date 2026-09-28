#include "_avc.h"
#undef assert
#ifdef NDEBUG
#define assert(x) ((void)0)
#else
AVC_BEGIN
__attribute__((noreturn)) void avc_assert_fail_(const char *, const char *, int) AVC_SYM(assert_fail);
AVC_END
#define assert(x) ((x) ? (void)0 : avc_assert_fail_(#x, __FILE__, __LINE__))
#endif
#if !defined(__cplusplus) && !defined(static_assert)
#define static_assert _Static_assert
#endif
