//
//  atc_parser.h
//  ATCParserKit — Unity iOS plugin
//
//  C interface exported by ATCParserFFI. Consumed from C# via P/Invoke
//  ([DllImport("__Internal")]). Not required for the C# binding to work
//  (P/Invoke resolves by symbol name), but provided for C/C++/Objective-C
//  callers and documentation.
//

#ifndef ATC_PARSER_H
#define ATC_PARSER_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Parse an ATC command transcript.
 * @param command  NUL-terminated UTF-8 transcript.
 * @return  Newly-allocated JSON C string. The caller owns it and MUST release
 *          it with atc_parser_free(). Returns a JSON error envelope on failure.
 */
const char *atc_parser_parse(const char *command);

/** Release a string returned by any function in this header. */
void atc_parser_free(char *pointer);

/* ---------------------------------------------------------------------------
 * Template-driven recognition.
 *
 * Unlike atc_parser_parse(), this holds state: the phraseology payload is
 * decoded once and reused, so the boundary is create / use / release.
 *
 * Ownership: every returned char* must be released with atc_parser_free(); a
 * handle must be released with atc_recognizer_release() and never used after.
 * A handle is not thread-safe — use one per thread or serialise access.
 * ------------------------------------------------------------------------ */

/**
 * Decode a phraseology payload and build a recognizer.
 * @param templates_json  NUL-terminated UTF-8 payload JSON.
 * @param error_json      Out-param, may be NULL. On failure and when non-NULL,
 *                        receives a newly-allocated JSON error envelope
 *                        ({"error":…,"detail":…}) that the caller must free
 *                        with atc_parser_free().
 * @return  Opaque handle, or NULL on failure.
 */
void *atc_recognizer_create(const char *templates_json, char **error_json);

/**
 * Recognise one transmission against the handle's payload.
 * @return  Newly-allocated result JSON (caller frees), or NULL if handle is
 *          NULL. An unrecognised transcript is not an error: the result has no
 *          commands and the text under "unrecognized".
 */
char *atc_recognizer_recognize(void *handle, const char *transcript);

/**
 * Problems found in the payload when it was decoded, plus template counts, as
 * JSON. A broken template otherwise fails silently as an instruction that never
 * matches, so this is worth logging at startup.
 * @return  Newly-allocated JSON (caller frees), or NULL if handle is NULL.
 */
char *atc_recognizer_diagnostics(void *handle);

/** Release a handle from atc_recognizer_create(). NULL is accepted. */
void atc_recognizer_release(void *handle);

#ifdef __cplusplus
}
#endif

#endif /* ATC_PARSER_H */
