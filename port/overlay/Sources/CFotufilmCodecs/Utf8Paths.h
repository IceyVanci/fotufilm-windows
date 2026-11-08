#ifndef FOTUFILM_CODECS_UTF8_PATHS_H
#define FOTUFILM_CODECS_UTF8_PATHS_H

/* Windows reads a narrow filename in the process's ANSI code page, which is the system's local
 * code page (GBK on a Chinese install). The engine's paths arrive as UTF-8 -- Dart hands the host
 * an UTF-8 C string -- so fopen, LibRaw and libtiff were all looking for a file whose name had been
 * decoded the wrong way, and a photograph under a Chinese directory opened as "not found".
 *
 * The character locale is the switch that decides that decoding; set it to UTF-8 once, when the
 * codec module loads. LC_CTYPE alone is enough and leaves the numeric locale (decimal point,
 * printf) exactly as the C runtime meant it. The two spellings cover the UCRT's name for the
 * locale and the code-page form older runtimes accept.
 *
 * Including this header in a translation unit that opens files registers the initializer for that
 * unit; the first one to run wins and the rest are no-ops. */
#if defined(_WIN32)
#include <clocale>

namespace fotufilm {
namespace detail {

struct Utf8PathLocale {
    Utf8PathLocale() {
        if (std::setlocale(LC_CTYPE, ".UTF-8") == nullptr) {
            std::setlocale(LC_CTYPE, ".utf8");
            std::setlocale(LC_CTYPE, ".65001");
        }
    }
};

[[maybe_unused]] static const Utf8PathLocale utf8PathLocale;

}  // namespace detail
}  // namespace fotufilm

#endif

#endif  /* FOTUFILM_CODECS_UTF8_PATHS_H */
