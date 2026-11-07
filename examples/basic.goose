// Run from the repository root:
//   goose run examples/basic.goose -- input.txt --name Ada -vc3 --format=CSV -Isrc --include=tests
//   goose run examples/basic.goose -- --help
// Prints the parsed settings; does not read or convert files.
import std;
import os;
import opts from "..";

enum Format { json, plain_text, CSV }

struct Options {
    input: opts::Field<const u8[:]> = opts::Field<const u8[:]> {
        help: "Input file", required: true, positional: true,
    },
    display_name: opts::Field<const u8[:]> = opts::Field<const u8[:]> {
        long: "name", short: "n", help: "Name to display", required: true,
    },
    count: opts::Field<i64> = opts::Field<i64> {
        value: 1, short: "c", help: "Number of copies",
    },
    verbose: opts::Field<bool> = opts::Field<bool> {
        short: "v", help: "Enable verbose output",
    },
    format: opts::Field<Format> = opts::Field<Format> {
        short: "f", help: "Output format",
    },
    include: opts::Field<(const u8[:])[]> = opts::Field<(const u8[:])[]> {
        value: [], short: "I", help: "Search directory",
    },
}

fn main() {
    // Keep argv and defaults alive: parsed strings borrow their storage.
    let argv = args();
    let defaults = Options {};
    let options, help_requested, error = opts::parse(argv[1..], defaults);
    if error.len > 0 {
        write_stderr(str(error, "\n"));
        exit(2);
    }
    if help_requested {
        write_stdout(opts::help("basic", copy(defaults), "Display parsed settings without reading files."));
        return;
    }
    print(
        options.input.value, " ", options.display_name.value, " ",
        options.count.value, " ", options.verbose.value, " ", options.format.value, " ", options.include.value,
    );
}
