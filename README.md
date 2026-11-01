# goosopt

Define command-line options as a struct in [Goose](https://github.com/aardappel/goose).
goosopt parses flags, values, and positional arguments, and generates help
from the descriptions you put on each field.

**[API reference and examples](API.md)** · [Complete example](examples/basic.goose)

Experimental: the API is not stable.

## Get started

Save this as `main.goose`. Goose downloads the package automatically:

```goose
import std;
import os;
import goosopt from "github.com/sstadick/goosopt@main";

struct Options {
    input: goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> {
        required: true, positional: true, help: "Input file",
    },
    count: goosopt::Field<i64> = goosopt::Field<i64> {
        value: 1, short: "c", help: "Number of copies",
    },
    verbose: goosopt::Field<bool> = goosopt::Field<bool> {
        short: "v", help: "Enable verbose output",
    },
}

fn main() {
    let argv = args();
    let options, help_requested, error = goosopt::parse<Options>(argv[1..]);
    if error.len > 0 {
        write_stderr(str(error, "\n"));
        exit(2);
    }
    if help_requested {
        write_stdout(goosopt::help<Options>("demo"));
        return;
    }
    print(options.input.value, " ", options.count.value, " ", options.verbose.value);
}
```

```sh
goose run main.goose -- input.txt --count 3 --verbose
# input.txt 3 true
goose run main.goose -- input.txt -c 3 -v
goose run main.goose -- --help
goose build main.goose -O2 -o demo
```

The library returns results; your program controls output and exit status.
Help text includes its final newline, so use `write_stdout` rather than `print`.
The [complete example](examples/basic.goose) also demonstrates required named
options and enum choices; it prints settings without reading any files.

The import above follows `main`. Pin a commit for a reproducible dependency.
Tested on Linux x86-64 with TinyCC, GCC, and Clang.

## Describe your options

Each member is a `Field<T>`, where `T` is `bool`, `i64`, `const u8[:]`, or
an enum whose variants have no payloads. Read parsed data through `.value`;
`.provided` tells you whether the user explicitly supplied that field.

| Field setting | Meaning |
| --- | --- |
| `value: 1` | Default when the user omits the option. Otherwise defaults to false, zero, an empty string, or the first enum variant. |
| `help: "Number of copies"` | Description in generated help. |
| `short: "c"` | Add `-c` as an alias. |
| `long: "dry-run"` | Use `--dry-run` instead of the struct member's name. |
| `required: true` | The user must supply this argument, even if it has a default. |
| `positional: true` | Take a positional argument rather than a named option. |

Without a `long` override, the field `dry_run` uses `--dry_run`.
Short names are one ASCII letter; `--help` and `-h` are reserved. Long names
can contain ASCII letters, digits, underscores, and hyphens, but cannot
start with a hyphen. Names must be unique within each long/short namespace.

Positionals are assigned in struct declaration order. Required positionals
must come before optional ones. They cannot be booleans or have option names.
Named options may appear before, between, or after positionals.

## Use enums for choices

The enum's variant names are the accepted CLI values:

```goose
enum Format { json, plain_text, CSV }
struct FormatOptions {
    format: goosopt::Field<Format> = goosopt::Field<Format> {
        value: Format.plain_text, short: "f", help: "Output format",
    },
}
```

`--format=json`, `--format CSV`, and `-fplain_text` return a typed `Format`
in `.value`. Names are case-sensitive: `csv`, `plain-text`, `Format.json`,
and numeric values are rejected. Enums also work as positionals. Without an
explicit `value`, the default is the enum's first variant.

Help shows `[choices: json, plain_text, CSV] [default: plain_text]`, and
invalid-value errors list the same choices. Variants with payloads are not
supported.

## Accepted arguments

| Argument | Effect |
| --- | --- |
| `--verbose` or `-v` | Set a boolean flag to true. |
| `--verbose=true` or `--verbose=false` | Explicitly set a boolean, including turning off a true default. |
| `--count 3`, `--count=3`, `-c 3`, or `-c3` | Set an integer option. Signed decimal values, including negatives, are accepted. |
| `-vc3` | Combine `-v` and `-c 3` in a short-option bundle. |
| `--name Seth` or `--name=Seth` | Set a string option, if your schema declares `name`. |
| `-- -filename` | Stop parsing options and treat the remaining tokens as positionals. |
| `--help` or `-h` | Request help without requiring missing arguments. |

Repeated options keep the last value. Strings may be empty or start with
`--`: `--name --help` assigns the literal string `--help` to `name`.
Use `--` before a negative positional number or a filename starting with `-`.
A lone `-` is always positional.

Short-option bundles run left to right. A value-taking option consumes the
remaining characters, or the next argument if none remain: `-vc-3` means
`-v -c -3`. Attached string values work too: `-nAda` supplies `Ada` when `n`
is a string option. An attached `=` is literal: `-n=foo` supplies `=foo`.

Explicit boolean values require a long option and `=true` or `=false`, in
lowercase. Other values are errors. Bare flags consume no value:
`--verbose false` sets verbose to true and leaves `false` as a positional
argument. Short flags do not accept explicit values (`-v=false`). Both
explicit true and false set `.provided` and satisfy a required boolean option.

Lists, subcommands, and other custom field types are not supported.

## Use the result safely

`parse` returns `options, help_requested, error`. Check the error first,
then help, and only use the options on success. Parsing stops at a help
request, so an earlier invalid argument still produces an error.

Use `.provided` when CLI arguments should override a config file only if
explicitly supplied. With the quickstart's count default of 1:

| Count argument | `options.count.value` | `options.count.provided` |
| --- | --- | --- |
| omitted | `1` | `false` |
| `--count 1` | `1` | `true` |
| `-c3` | `3` | `true` |

Presence tracks flags, values, and positionals, including false, zero, or an
empty string. Each parse resets presence, even when reusing a parsed result
as defaults. Required fields must be supplied on every parse. The caller's
defaults are unchanged.

Strings **borrow the argument storage**. Keep it alive while using the
result. Bind argument arrays to a variable rather than passing a temporary
array literal, and omit the program name when passing process arguments.

Use `parse<Options>(argv)` for the defaults declared on your struct. To
supply different defaults, use `parse(argv, defaults)`. Generate matching
help with `help(program, defaults, description)`, passing the original
defaults rather than the parsed result. The description is optional.

## Add zsh completion

The generated help works with zsh's `_gnu_generic` option completion.
After building the example above, run this in an interactive zsh with
completion initialized:

```sh
compdef _gnu_generic ./demo
```

This completes option names, not positional arguments or enum choices.
Value-taking options complete with `=`; both `--count=3` and `--count 3`
are accepted.

## Contributing

Run tests with Python 3, Goose, and a native C compiler:

```sh
python3 test/run.py --goose /path/to/goose --cc gcc
python3 test/run.py --goose /path/to/goose --cc clang --zsh zsh
```

The second command also requires zsh and tests interactive completion.

Edit API documentation in source comments, not `API.md`. With
[goosdoc v0.2.0](https://github.com/sstadick/goosdoc/releases/tag/v0.2.0)
checked out at `../goosdoc`, run:

```sh
scripts/docs.sh
scripts/docs.sh --check
scripts/doctest.sh
scripts/doctest.sh --cc gcc
scripts/doctest.sh --cc clang
```

Set `GOOSDOC=/path/to/goosdoc/main.goose` for another location. Every API
declaration needs an executable example; imports and shared types belong in
[test/doc_preamble.goose](test/doc_preamble.goose). See the
[example conventions](https://github.com/sstadick/goosdoc#executable-examples).
CI checks documentation and tests before publishing version-tagged releases.

## License

MIT; see [LICENSE](LICENSE).
