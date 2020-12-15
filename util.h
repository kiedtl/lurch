#ifndef UTIL_H
#define UTIL_H

#define UNUSED(VAR) ((void) (VAR))
#define IS_STRINT(CHAR) ((CHAR) <= '9' && (CHAR) >= '0')

void die(const char *fmt, ...);
char *format(const char *format, ...);
void cleanup(void);

#endif
