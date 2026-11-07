import std;
import opts from "..";

struct Options {
    input: opts::Field<const u8[:]> = opts::Field<const u8[:]> {
        required: true, positional: true, help: "Input file",
    },
    count: opts::Field<i64> = opts::Field<i64> {
        value: 1, short: "c", help: "Number of copies",
    },
    verbose: opts::Field<bool> = opts::Field<bool> { short: "v" },
}

enum Format { json, plain_text, CSV }
struct FormatOptions {
    format: opts::Field<Format> = opts::Field<Format> {
        value: Format.plain_text, short: "f", help: "Output format",
    },
}

struct IncludeOptions {
    include: opts::Field<(const u8[:])[]> = opts::Field<(const u8[:])[]> {
        value: [], short: "I", help: "Search directory",
    },
}
