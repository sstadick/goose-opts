import std;
import goosopt from "..";

struct Options {
    input: goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> {
        required: true, positional: true, help: "Input file",
    },
    count: goosopt::Field<i64> = goosopt::Field<i64> {
        value: 1, short: "c", help: "Number of copies",
    },
    verbose: goosopt::Field<bool> = goosopt::Field<bool> { short: "v" },
}

enum Format { json, plain_text, CSV }
struct FormatOptions {
    format: goosopt::Field<Format> = goosopt::Field<Format> {
        value: Format.plain_text, short: "f", help: "Output format",
    },
}
