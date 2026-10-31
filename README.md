# goosopt

An experimental, minimal struct-derived CLI parser for
[Goose](https://github.com/aardappel/goose), inspired by
[mojopt](https://github.com/sstadick/mojopt) and Rust's structopt.
**The API is not stable.**

Goose's `const for <Name, Access> in fields<T>` generates field access at
compile time. Values and CLI metadata live together in `Field<T>` wrappers
on your options struct. There is no separate spec, macro, code-generation
step, or C dependency.

See the generated [API reference](API.md) for `Field`, `parse`, and `help`,
including executable examples.

## Try it

With Goose on your PATH, from this checkout:

```sh
goose run examples/basic.goose -- input.txt --name Seth --count 3 --verbose
# input.txt Seth 3 true
goose run examples/basic.goose -- input.txt -n Seth -c 3 -v
goose run examples/basic.goose -- --help
```

Declare defaults, names, descriptions, and required/positional behavior on
the fields themselves:

```goose
import std;
import goosopt from "github.com/sstadick/goosopt@main";

struct Options {
    input: goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> {
        required: true, positional: true, help: "Input file"
    },
    count: goosopt::Field<i64> = goosopt::Field<i64> {
        value: 1, short: "c", help: "Number of copies"
    },
    verbose: goosopt::Field<bool> = goosopt::Field<bool> {},
}

fn main() {
    let argv = ["input.txt", "--count=3", "--verbose"];
    let options, help_requested, error = goosopt::parse<Options>(argv);
    if error.len > 0 { print(error); return; }
    if help_requested {
        print(goosopt::help<Options>("demo"));
        return;
    }
    print(options.input.value, " ", options.count.value, " ", options.verbose.value);
}
```

For process arguments, import `os`, bind `let argv = args()`, and pass
`argv[1..]`, excluding the program name. The [example](examples/basic.goose)
also demonstrates a required named option. The library never prints or exits:
the example writes errors to stderr and exits with status 2, or writes help
to stdout and exits successfully.

## Required fields and positionals

Every options member is a `Field<T>` for `bool`, `i64`, or `const u8[:]`.
`value` defaults to `false`, `0`, or an empty string. `help`, `long`, and
`short` default to `""`; `required` and `positional` default to `false`.
Use `parse<Options>(argv)` for declared defaults, or
`parse(argv, defaults)` to supply a configured options instance.

- `required: true` means the user must supply the field, regardless of its
  initial value. No `value` initializer is needed for a required field.
  An explicitly supplied `0` or `""` satisfies the requirement.
- `positional: true` consumes one argument in **struct declaration order**,
  and cannot have `long` or `short` names. Required positionals must precede
  optional ones. An omitted optional positional keeps its supplied default.
- Named options can appear before, between, or after positionals. `--` ends
  option processing: subsequent tokens are positional, even `--help` or `-5`.
  Use it for negative positional numbers and filenames starting with `-`.
  A lone `-` is always positional.
- Requiredness is explicit, not inferred from the presence of a `value`
  initializer. A `Field<i64> {}` is optional and defaults to zero.

## Option names

Without `long`, the struct field name is used: `dry_run` becomes `--dry_run`.
Set `long: "dry-run"` to replace it with `--dry-run`; `--dry_run` is then
unknown. Set `short: "d"` to add `-d`. The example's `display_name` field
uses `long: "name", short: "n"`, so callers use `--name` or `-n`.

Long names contain ASCII letters, digits, underscores, and hyphens, but
cannot start with a hyphen. Short names must be one ASCII letter and are
case-sensitive. `--help` and `-h` are reserved. Duplicate names, invalid
names, boolean positionals, and optional-before-required positional layouts
return schema errors before parsing any arguments.

## Parsing contract

- `bool`: `--verbose` sets the field to `true`; consumes no value.
- `i64`: `--count -3` or `--count=-3` consumes a signed decimal integer,
  checked for overflow.
- `const u8[:]`: `--name text` or `--name=text` consumes a string, including
  an empty string or a token beginning with `--`. Thus `--name --help` assigns
  the literal value `--help`; it does not request help.
- Strings borrow the argument bytes. Keep that storage alive while using
  the result, and bind argument arrays to a variable rather than passing a
  temporary array literal.
- Short options accept separate or attached values: `-c -3` or `-c-3`.
  Bundles run left to right: `-vc3` means `-v -c 3`. A value-taking option
  consumes the remaining characters, or the next argument if none remain.
  An attached `=` is literal: `-n=foo` supplies `=foo`, not `foo`.
- Repeated options use the last value. Flags do not accept `=value`.
- `parse` returns `options, help_requested, error`. An empty error with
  `help_requested == false` means success. Read values through `.value`.
  Defaults and field metadata are unchanged. Discard the options on error
  or help; they may be partially parsed.
- Unknown options, excess positionals, missing required fields/values, and
  invalid integers return an error. Unsupported field types fail compilation.

## Help and zsh completion

`-h` and `--help` request help without checking missing required fields.
Arguments are processed left to right: an earlier malformed option still
fails; tokens after a help request are not processed. Metadata is validated
first.

Call `goosopt::help<Options>(program)` or
`goosopt::help(program, defaults, description)` after `parse` reports a help
request. Pass the original defaults, not the parsed result. The description
is optional. Help lists required fields, defaults, positional arguments,
and value placeholders, including required options in Usage.

The GNU-style option lines are tested with zsh's **`compdef _gnu_generic`**,
the same completion helper used for mojopt. For a built example:

```sh
goose build examples/basic.goose -o basic
# In an interactive zsh with completion initialized:
compdef _gnu_generic ./basic
```

Value-taking options use `--name=NAME` in help so zsh completes them with
`=`; both attached and separate values work. This is tested option-completion
compatibility, not a claim of full GNU CLI compliance. `_gnu_generic` does
not derive our positional schema from help.

Still intentionally absent: lists, subcommands, and custom field types.

## Development

Uses the same pure package layout and test conventions as goosimd. No
`.build` file is needed. Tested with Goose revision
`b46099024b9af8a9f54cd76e24953a89c21ccb3a`, also pinned in CI.

```sh
python3 test/run.py --goose /path/to/goose --cc gcc
python3 test/run.py --goose /path/to/goose --cc clang --zsh zsh
```

Tests use a fresh `GOOSE_HOME`, TinyCC at `-O0`/`-O2`, native builds, and
the real example CLI's stdout, stderr, and exit status. With zsh installed,
they also open an interactive shell and exercise actual tab completion;
`--zsh` makes its availability mandatory. CI always runs this check.
Coverage includes required/default values, positional ordering, `--`, help
versus literal values, short/long names, schema errors, repeats, and integer boundaries.
Verified platform: Linux x86-64, with zsh 5.9.

### Generated API reference

Like goostr and goosimd, goosopt uses
[goosdoc](https://github.com/sstadick/goosdoc) v0.2.0, pinned in CI.
With that checkout beside this one:

```sh
GOOSE=/path/to/goose scripts/docs.sh
GOOSE=/path/to/goose scripts/docs.sh --check
GOOSE=/path/to/goose scripts/doctest.sh
GOOSE=/path/to/goose scripts/doctest.sh --cc gcc
GOOSE=/path/to/goose scripts/doctest.sh --cc clang
# Override its location if needed:
GOOSDOC=/path/to/goosdoc/main.goose scripts/docs.sh --check
```

Edit source comments, not `API.md`. `api.txt` lists the public symbols;
generation requires documentation and a runnable example for every listed
declaration. Write examples as `fn main()` bodies in `goose` fences inside
the declaration's `//` comments, using `assert` to check results. Imports and
the example `Options` struct come from [test/doc_preamble.goose](test/doc_preamble.goose).
Each example runs independently against this checkout. Running examples
requires Python 3 as well as Goose; see goosdoc's
[example conventions](https://github.com/sstadick/goosdoc#executable-examples).

CI rejects missing or failing examples, checks that `API.md` is current,
and uploads an `api-reference` artifact with source links pinned to the
tested commit. Examples run under TinyCC, GCC, and Clang.

CI runs on pushes and pull requests. Following goosimd, versions will be
Git tags (`vMAJOR.MINOR.PATCH`); pushing a version tag publishes a GitHub
source release with the generated API reference only after tests pass.
No release exists yet.

MIT; see [LICENSE](LICENSE).
