// Run from the repository root:
//   goose run examples/basic.goose -- input.txt --name Ada -vc3 --format=CSV
//   goose run examples/basic.goose -- --help
// Prints the parsed settings; does not read or convert files.
import std;
import os;
import goosopt from "..";

enum Format { json, plain_text, CSV }

struct Options {
    input: goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> {
        help: "Input file", required: true, positional: true,
    },
    display_name: goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> {
        long: "name", short: "n", help: "Name to display", required: true,
    },
    count: goosopt::Field<i64> = goosopt::Field<i64> {
        value: 1, short: "c", help: "Number of copies",
    },
    verbose: goosopt::Field<bool> = goosopt::Field<bool> {
        short: "v", help: "Enable verbose output",
    },
    format: goosopt::Field<Format> = goosopt::Field<Format> {
        short: "f", help: "Output format",
    },
}

fn main() {
    // Keep argv alive: parsed strings borrow its storage.
    let argv = args();
    let options, help_requested, error = goosopt::parse<Options>(argv[1..]);
    if error.len > 0 {
        write_stderr(str(error, "\n"));
        exit(2);
    }
    if help_requested {
        write_stdout(goosopt::help("basic", Options {}, "Display parsed settings without reading files."));
        return;
    }
    print(
        options.input.value, " ", options.display_name.value, " ",
        options.count.value, " ", options.verbose.value, " ", options.format.value,
    );
}
