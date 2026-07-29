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

/** Release a string returned by atc_parser_parse(). */
void atc_parser_free(char *pointer);

#ifdef __cplusplus
}
#endif

#endif /* ATC_PARSER_H */
