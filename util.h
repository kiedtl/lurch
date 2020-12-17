#ifndef UTIL_H
#define UTIL_H

#define UNUSED(VAR) ((void) (VAR))
#define NETWRK_ERR() \
	(tls_active ? tls_error(client) : strerror(errno))

void die(const char *fmt, ...);
char *format(const char *format, ...);
void cleanup(void);

#endif
