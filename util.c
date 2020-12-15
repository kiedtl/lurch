#include <assert.h>
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "termbox.h"
#include "util.h"

extern FILE *conn;
extern size_t TB_ACTIVE;
extern size_t TB_INACTIVE;
extern size_t tb_state;

void
die(const char *fmt, ...)
{
	if (tb_state == TB_ACTIVE) {
		tb_shutdown();
		tb_state = TB_INACTIVE;
	}

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
		fprintf(stderr, "NOTE: set $LURCH_DEBUG >0 for backtrace\n");
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

char *
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
	if (tb_state == TB_ACTIVE) {
		tb_shutdown();
		tb_state = TB_INACTIVE;
	}

	if (conn) fclose(conn);

	/*
	 * Don't call lua_close, as this function may be
	 * called by lua itself.
	 *
	 * Anyway, the memory will be freed when lurch
	 * exits.
	 */
}
