/* printf family for the libc replacement (libc/include/stdio.h). C, because Zig 0.16 cannot
   define variadic C functions on every target (VaList is disabled on aarch64-linux, x86_64-windows).
   Supports %% %c %s %d %i %u %x %X %p, flags '-' '0', width, precision (%s only), h hh l ll z j t. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

struct out { char *buf; size_t cap; size_t len; };

static void put(struct out *o, char c) {
	if (o->len + 1 < o->cap) o->buf[o->len] = c;
	o->len++;
}

static void pad(struct out *o, char c, int n) {
	while (n-- > 0) put(o, c);
}

static void field(struct out *o, const char *s, size_t n, int width, int left, char fill) {
	int gap = width > (int)n ? width - (int)n : 0;
	if (!left) {
		/* keep the sign in front of zero padding */
		if (fill == '0' && n > 0 && *s == '-') { put(o, *s++); n--; }
		pad(o, fill, gap);
	}
	while (n--) put(o, *s++);
	if (left) pad(o, ' ', gap);
}

int vsnprintf(char *buf, size_t cap, const char *fmt, va_list ap) {
	struct out o = { buf, cap, 0 };
	for (; *fmt; fmt++) {
		if (*fmt != '%') { put(&o, *fmt); continue; }
		fmt++;
		int left = 0; char fill = ' ';
		for (;; fmt++) {
			if (*fmt == '-') left = 1;
			else if (*fmt == '0') fill = '0';
			else if (*fmt != '+' && *fmt != ' ' && *fmt != '#') break;
		}
		int width = 0, prec = -1;
		if (*fmt == '*') { width = va_arg(ap, int); fmt++; }
		else while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
		if (*fmt == '.') {
			fmt++; prec = 0;
			if (*fmt == '*') { prec = va_arg(ap, int); fmt++; }
			else while (*fmt >= '0' && *fmt <= '9') prec = prec * 10 + (*fmt++ - '0');
		}
		int size = 0; /* 0 int, 1 long, 2 long long, 3 size_t/intmax/ptrdiff */
		for (;; fmt++) {
			if (*fmt == 'h') continue;
			else if (*fmt == 'l') size++;
			else if (*fmt == 'z' || *fmt == 'j' || *fmt == 't') size = 3;
			else break;
		}
		char tmp[24];
		char *end = tmp + sizeof tmp, *p = end;
		switch (*fmt) {
		case '%': put(&o, '%'); break;
		case 'c': tmp[0] = (char)va_arg(ap, int); field(&o, tmp, 1, width, left, ' '); break;
		case 's': {
			const char *s = va_arg(ap, const char *);
			if (!s) s = "(null)";
			size_t n = strlen(s);
			if (prec >= 0 && (size_t)prec < n) n = (size_t)prec;
			field(&o, s, n, width, left, ' ');
			break;
		}
		case 'd': case 'i': {
			long long v = size == 0 ? va_arg(ap, int) : size == 1 ? va_arg(ap, long)
				: size == 2 ? va_arg(ap, long long) : (long long)va_arg(ap, intptr_t);
			unsigned long long u = v < 0 ? 0ull - (unsigned long long)v : (unsigned long long)v;
			do *--p = (char)('0' + u % 10); while (u /= 10);
			if (v < 0) *--p = '-';
			field(&o, p, (size_t)(end - p), width, left, fill);
			break;
		}
		case 'u': case 'x': case 'X': case 'p': {
			unsigned long long u;
			if (*fmt == 'p') u = (uintptr_t)va_arg(ap, void *);
			else u = size == 0 ? va_arg(ap, unsigned) : size == 1 ? va_arg(ap, unsigned long)
				: size == 2 ? va_arg(ap, unsigned long long) : (unsigned long long)va_arg(ap, size_t);
			unsigned base = *fmt == 'u' ? 10 : 16;
			const char *digits = *fmt == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
			do *--p = digits[u % base]; while (u /= base);
			if (*fmt == 'p') { *--p = 'x'; *--p = '0'; }
			field(&o, p, (size_t)(end - p), width, left, fill);
			break;
		}
		default: /* unsupported conversion (floats, %n): stop, like a truncated write */
			goto done;
		}
	}
done:
	if (cap > 0) buf[o.len < cap ? o.len : cap - 1] = 0;
	return (int)o.len;
}

int snprintf(char *buf, size_t cap, const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(buf, cap, fmt, ap);
	va_end(ap);
	return n;
}

int vsprintf(char *buf, const char *fmt, va_list ap) {
	return vsnprintf(buf, SIZE_MAX, fmt, ap);
}

int sprintf(char *buf, const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(buf, SIZE_MAX, fmt, ap);
	va_end(ap);
	return n;
}

/* There are no files: output to a FILE is discarded. */
int vfprintf(FILE *f, const char *fmt, va_list ap) { (void)f; (void)fmt; (void)ap; return 0; }
int vprintf(const char *fmt, va_list ap) { (void)fmt; (void)ap; return 0; }
int fprintf(FILE *f, const char *fmt, ...) { (void)f; (void)fmt; return 0; }
int printf(const char *fmt, ...) { (void)fmt; return 0; }
