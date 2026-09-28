#ifndef AVC_MATH_H
#define AVC_MATH_H
#include "_avc.h"
#define M_E 2.7182818284590452354
#define M_LN2 0.69314718055994530942
#define M_LN10 2.30258509299404568402
#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_SQRT2 1.41421356237309504880
#define M_SQRT1_2 0.70710678118654752440
#define HUGE_VAL __builtin_huge_val()
#define HUGE_VALF __builtin_huge_valf()
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define FP_NAN 0
#define FP_INFINITE 1
#define FP_ZERO 2
#define FP_SUBNORMAL 3
#define FP_NORMAL 4
#define fpclassify(x) __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, x)
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#define isfinite(x) __builtin_isfinite(x)
#define isnormal(x) __builtin_isnormal(x)
#define signbit(x) __builtin_signbit(x)
AVC_BEGIN
/* compiler_rt */
double sin(double); float sinf(float);
double cos(double); float cosf(float);
double tan(double); float tanf(float);
double exp(double); float expf(float);
double exp2(double); float exp2f(float);
double log(double); float logf(float);
double log2(double); float log2f(float);
double log10(double); float log10f(float);
double fabs(double); float fabsf(float);
double floor(double); float floorf(float);
double ceil(double); float ceilf(float);
double round(double); float roundf(float);
double trunc(double); float truncf(float);
double fmod(double, double); float fmodf(float, float);
double fma(double, double, double); float fmaf(float, float, float);
double fmin(double, double); float fminf(float, float);
double fmax(double, double); float fmaxf(float, float);
double sqrt(double); float sqrtf(float);
/* src/libc.zig */
double pow(double, double) AVC_SYM(pow); float powf(float, float) AVC_SYM(powf);
double acos(double) AVC_SYM(acos); float acosf(float) AVC_SYM(acosf);
double asin(double) AVC_SYM(asin); float asinf(float) AVC_SYM(asinf);
double atan(double) AVC_SYM(atan); float atanf(float) AVC_SYM(atanf);
double atan2(double, double) AVC_SYM(atan2); float atan2f(float, float) AVC_SYM(atan2f);
double sinh(double) AVC_SYM(sinh); double cosh(double) AVC_SYM(cosh); double tanh(double) AVC_SYM(tanh);
float tanhf(float) AVC_SYM(tanhf);
double ldexp(double, int) AVC_SYM(ldexp); float ldexpf(float, int) AVC_SYM(ldexpf);
double frexp(double, int *) AVC_SYM(frexp); float frexpf(float, int *) AVC_SYM(frexpf);
double modf(double, double *) AVC_SYM(modf);
double hypot(double, double) AVC_SYM(hypot);
long lrint(double) AVC_SYM(lrint); long lrintf(float) AVC_SYM(lrintf);
long lround(double) AVC_SYM(lround); long lroundf(float) AVC_SYM(lroundf);
double rint(double) AVC_SYM(rint); float rintf(float) AVC_SYM(rintf);
AVC_END
#endif
