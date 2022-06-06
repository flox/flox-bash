/*
 * flox wrapper - set environment variables prior to launching flox
 */

#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>
#include <syslog.h>

#define LOG_STRERROR ": %m"

/*
 * Print and log a fatal error message (including a system error), and die.
 */
static void __attribute__((noreturn, format(printf, 1, 2)))
fatal(const char *format, ...)
{
	va_list ap;

	size_t len = strlen(format);
	char *sformat = alloca(len + sizeof(LOG_STRERROR));
	strcpy(sformat, format);
	strcpy(sformat + len, LOG_STRERROR);

	va_start(ap, format);
	vsyslog(LOG_ERR, sformat, ap);
	va_end(ap);

	va_start(ap, format);
	verr(EXIT_FAILURE, format, ap);
	va_end(ap);
}


int
main(int argc, char **argv)
{
	/*
	 * XXX Nixpkgs itself is broken in that the packages it creates
	 * depends upon the LOCALE_ARCHIVE path being set to point to
	 * the full locale-archive file. This is usually set for users
	 * by NixOS and the client-side nix programs (e.g. nix-env) but
	 * that breaks the portability of Nix-compiled packages copied
	 * to other systems and containers where Nix/NixOS is not used.
	 *
	 * For flox specifically, set a reasonable default for the
	 * LOCALE_ARCHIVE variable if it is not already set while we
	 * work to convince the Nix community that this is a problem
	 * to be fixed in Nixpkgs itself.
	 */
	char *localeArchive = getenv("LOCALE_ARCHIVE");
	if (localeArchive == NULL) {
		if (setenv("LOCALE_ARCHIVE", LOCALE_ARCHIVE, 1) != 0)
			fatal("setenv");
	}

	/*
	 * Run the command.
	 */
	execvp(FLOXSH, argv);
	fatal("%s", FLOXSH);
}
