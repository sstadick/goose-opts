import std;
import goosopt from "..";

struct Options {
    input: goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> {
        required: true, positional: true, help: "Input file",
    },
    count: goosopt::Field<i64> = goosopt::Field<i64> {
        value: 1, short: "c", help: "Number of copies",
    },
}
