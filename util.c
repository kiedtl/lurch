#include <assert.h>
#include <execinfo.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tls.h>
#include <unistd.h>

#include "termbox.h"
#include "util.h"

extern int conn_fd;
extern struct tls *client;
extern _Bool tls_active;

extern size_t tb_status;
extern size_t TB_ACTIVE;

_Noreturn void __attribute__((format(printf, 1, 2)))
die(const char *fmt, ...)
{
	fprintf(stderr, "fatal: ");

	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);

	if (fmt[0] && fmt[strlen(fmt) - 1] == ':') {
		perror(" ");
	} else {
		fputc('\n', stderr);
	}

	char *buf_sz_str = getenv("LURCH_DEBUG");

	if (buf_sz_str == NULL) {
		fprintf(stderr, "NOTE: set $LURCH_DEBUG >0 for a backtrace.\n");
	} else {
		size_t buf_sz = strtol(buf_sz_str, NULL, 10);
		void *buffer[buf_sz];

		int nptrs = backtrace(buffer, buf_sz);
		char **strings = backtrace_symbols(buffer, nptrs);
		assert(strings);

		fprintf(stderr, "backtrace:\n");
		for (size_t i = 0; i < (size_t) nptrs; ++i)
			fprintf(stderr, "   %s\n", strings[i]);
		free(strings);
	}

	exit(1);
}

char * __attribute__((format(printf, 1, 2)))
format(const char *fmt, ...)
{
	static char buf[4096];
	va_list ap;
	va_start(ap, fmt);
	int len = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	assert((size_t) len < sizeof(buf));
	return (char *) &buf;
}

void
cleanup(void)
{
	if (tls_active && client) {
		tls_close(client);
		tls_free(client);
	} else if (conn_fd != 0) {
		close(conn_fd);
		conn_fd = 0;
	}

	if ((tb_status & TB_ACTIVE) == TB_ACTIVE) {
		tb_shutdown();
		tb_status ^= TB_ACTIVE;
	}
}
