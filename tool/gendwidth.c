#define UTF8_MAX 0x10FFFF

#include <stdio.h>
#include <utf8proc.h>

int
main(void)
{
	size_t cols = 0;

	printf(
		"#include <stddef.h>\n"
		"#include \"dwidth.h\"\n"
		"const size_t dwidth[] = {\n"
		"\t"
	);

	for (size_t i = 0; i < UTF8_MAX; ++i) {
		size_t w = utf8proc_charwidth((utf8proc_int32_t) i);
		cols += printf("[%zu] = %zu, ", i, w);

		if ((cols + 7) >= 80) {
			printf("\n\t");
			cols = 0;
		}
	}
	printf("\n};\n");
}
