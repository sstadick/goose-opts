// Typed command-line options, positional arguments, and help text.
namespace opts;
import std;

// Declare an option or positional argument as a member of your options struct.
// T can be `bool`, `i64`, `const u8[:]`, an enum with no variant payloads,
// or `(const u8[:])[]` for repeated string options.
//
// | Member | Meaning |
// | --- | --- |
// | `value` | Default before parsing; parsed value afterward. Defaults to false, zero, an empty string, or the first enum variant. |
// | `help` | Description shown in generated help. |
// | `required` | Require explicit input, even when a default exists. |
// | `positional` | Consume a positional argument instead of a named option. |
// | `long` | Override the option name; empty uses the struct member's name. |
// | `short` | Optional one-letter alias. |
// | `provided` | Whether this parse read the field from argv, including a value equal to its default. |
//
// Parsing changes only `value` and `provided` in the returned struct. Presence
// starts false on each parse; setting it in defaults does not satisfy `required`.
// The caller's defaults are unchanged.
//
// Long names contain ASCII letters, digits, underscores, and hyphens, and cannot
// start with a hyphen. Short names are ASCII letters. Names must be unique within
// each long/short namespace; `--help` and `-h` are reserved.
//
// Positionals consume one token in declaration order. Required positionals must
// precede optional ones. They cannot be booleans or have long or short names.
// Enum values use exact, case-sensitive variant names without a type prefix.
// Help and invalid-value errors list the accepted names.
//
// String arrays collect one value per occurrence, preserving order, duplicates,
// and empty strings. Explicit input replaces defaults; omission retains them.
// Arrays require an explicit `value: []` or populated default and cannot be
// positional. A required array needs at least one occurrence, even if empty.
//
// ```goose
// let count = opts::Field<i64> { value: 3, short: "c", help: "Number of copies" };
// assert(count.value == 3 && count.short == "c" && !count.required);
// assert(!count.provided);
// let input = opts::Field<const u8[:]> { required: true, positional: true };
// assert(input.value == "" && input.required && input.positional);
// ```
//
// Using `enum Format { json, plain_text, CSV }` from the
// [example preamble](test/doc_preamble.goose):
//
// ```goose
// let output = opts::Field<Format> { value: Format.plain_text, short: "f" };
// assert(output.value == Format.plain_text && !output.provided);
// let include = opts::Field<(const u8[:])[]> { value: [], short: "I" };
// assert(include.value.len == 0 && !include.provided);
// ```
struct Field<T> {
    value:      T           = default<T>(),
    help:       const u8[:] = "",
    required:   bool        = false,
    positional: bool        = false,
    long:       const u8[:] = "",
    short:      const u8[:] = "",
    provided:   bool        = false,
}

fn option_name(name: const u8[:], long: const u8[:]) -> const u8[:] {
    return if long.len > 0 { long } else { name };
}

fn ascii_letter(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn valid_long(name: const u8[:]) -> bool {
    if name.len == 0 { return false; }
    for i in name.len {
        let c = name[i];
        if !ascii_letter(c) && !(c >= '0' && c <= '9') && c != '_' && !(i > 0 && c == '-') {
            return false;
        }
    }
    return true;
}

fn is_flag(value: bool) -> bool { return true; }
fn is_flag<T>(value: T) -> bool { return false; }

fn is_repeated(value: (const u8[:])[]&) -> bool { return true; }
fn is_repeated<T>(value: T) -> bool { return false; }

fn validate<T>(options: T&) -> u8[>..] {
    var optional_positional = false;
    var long_names:  (const u8[:])[>..] = [];
    var short_names: (const u8[:])[>..] = [];
    const for <Name, Access> in fields<T> {
        let field = options.Access;
        if field.positional {
            if field.long.len > 0 || field.short.len > 0 {
                return str("positional cannot have option names: ", Name);
            }
            if is_flag(field.value) { return str("boolean positional is not supported: ", Name); }
            if is_repeated(field.value) { return str("repeated positional is not supported: ", Name); }
            if field.required && optional_positional {
                return str("required positional follows optional positional: ", Name);
            }
            if !field.required { optional_positional = true; }
        } else {
            let long_name = option_name(Name, field.long);
            if !valid_long(long_name) { return str("invalid long option name: ", long_name); }
            if long_name == "help" { return "reserved option name: --help"; }
            if contains(long_names[..], long_name) { return str("duplicate long option: --", long_name); }
            long_names.push(long_name);
            if field.short.len > 0 {
                if field.short.len != 1 || !ascii_letter(field.short[0]) {
                    return str("short option must be one ASCII letter: ", field.short);
                }
                if field.short == "h" { return "reserved option name: -h"; }
                if contains(short_names[..], field.short) { return str("duplicate short option: -", field.short); }
                short_names.push(field.short);
            }
        }
    }
    return "";
}

// Parse argv into an options struct whose members are `Field<T>` wrappers.
// Use `parse<Options>(argv)` for declared defaults or `parse(argv, defaults)`
// to supply your own. For process arguments, bind `let argv = args();` and
// pass `argv[1..]` to exclude the program name. See the
// [complete example](examples/basic.goose).
//
// Returns `options, help_requested, error`. Check error first, then help.
// Use options only when error is empty and help_requested is false; otherwise
// they may be partial. The library does not print or exit.
//
// Strings borrow argument bytes. Bind argv to a variable and keep its storage
// alive while using the result. The caller's defaults are unchanged, and each
// field's `provided` reports input from this parse only.
// The result owns its array of string slices, not their referenced bytes.
// When passing bound array defaults, keep those defaults alive too, or pass
// `copy(defaults)` to preserve the lifetimes of their referenced bytes directly.
//
// - Integers, strings, and enums accept `--name VALUE`, `--name=VALUE`,
//   `-n VALUE`, or `-nVALUE`. Scalars keep the last value. String arrays
//   accept the same forms and collect every value, without splitting commas.
// - Bare boolean flags set true without consuming a value. Long flags also
//   accept `=true` or `=false`, lowercase only; short flags do not.
// - Short bundles run left to right. A value-taking option consumes the rest
//   of the token, or the next argument: `-vc3` means `-v -c 3`.
//   An attached `=` is literal for short options: `-n=foo` supplies `=foo`.
// - `--` ends option processing. A lone `-` is positional. Named options may
//   appear before, between, or after positionals.
// - `-h`/`--help` bypass missing required fields, but not invalid field settings
//   or earlier parse errors. As a value, `--help` is ordinary input.
//
// Using `Options` from the [example preamble](test/doc_preamble.goose), with
// a required input positional, count defaulting to 1, and a verbose flag:
//
// ```goose
// let argv = ["input.txt", "-vc3"];
// let options, help_requested, error = opts::parse<Options>(argv);
// assert(error == "" && !help_requested);
// assert(options.input.value == "input.txt" && options.count.value == 3);
// assert(options.verbose.value);
// assert(options.input.provided && options.count.provided && options.verbose.provided);
// ```
//
// Override defaults and distinguish omitted values from explicit input:
//
// ```goose
// var defaults = Options {};
// defaults.count.value = 3;
// defaults.verbose.value = true;
// let argv = ["input.txt", "--verbose=false"];
// let options, help_requested, error = opts::parse(argv, defaults);
// assert(error == "" && !help_requested);
// assert(options.count.value == 3 && !options.count.provided);
// assert(!options.verbose.value && options.verbose.provided);
// ```
//
// Enum options return typed values. `FormatOptions` in the preamble declares
// a `Field<Format>` with `json`, `plain_text`, and `CSV` as its choices:
//
// ```goose
// let argv = ["--format=CSV"];
// let options, help_requested, error = opts::parse<FormatOptions>(argv);
// assert(error == "" && !help_requested);
// assert(options.format.value == Format.CSV && options.format.provided);
// ```
//
// `IncludeOptions` in the preamble declares a repeated string option:
//
// ```goose
// let defaults = IncludeOptions {};
// let argv = ["-Isrc", "--include", "tests", "--include=src"];
// let options, help_requested, error = opts::parse(argv, defaults);
// assert(error == "" && !help_requested && options.include.provided);
// assert(options.include.value.len == 3);
// assert(options.include.value[0] == "src" && options.include.value[1] == "tests");
// assert(options.include.value[2] == "src" && defaults.include.value.len == 0);
// ```
fn parse<T, S>(argv: S[:], defaults: T = T { .. }) {
    // Normalize array-containing lvalues to owned values before inferring T.
    return parse_options(argv, copy(defaults));
}

fn parse_options<T, S>(argv: S[:], options: T) -> T, bool, u8[>..] {
    // Owned arrays cannot resize: collect occurrences, then construct the result.
    var supplied: Occurrence[>..] = [];
    var i = 0;

    fn result_field(field: Field<(const u8[:])[]>, name: const u8[:]) -> Field<(const u8[:])[]> {
        var values: (const u8[:])[>..] = [];
        for source in supplied {
            if source.name == name { values.push(argv[source.index][source.offset..]); }
        }
        if values.len == 0 {
            var out = copy(field);
            out.provided = false;
            return out;
        }
        return Field<(const u8[:])[]> {
            value:      copy(values), help: field.help, required: field.required,
            positional: field.positional, long: field.long, short: field.short, provided: true,
        };
    }

    fn result_field<U>(field: Field<U>, name: const u8[:]) -> Field<U> {
        var out = copy(field);
        out.provided = false;
        var last = -1;
        for j in supplied.len { if supplied[j].name == name { last = j; } }
        if last >= 0 {
            let source = supplied[last];
            let text = if source.flag { "true" } else { argv[source.index][source.offset..] };
            // Each occurrence was validated before being recorded.
            read_value(&out.value, text);
            out.provided = true;
        }
        return out;
    }

    fn result() -> T {
        return T { const for <Name, Access> in fields<T> { Access: result_field(copy(options.Access), Name), } };
    }

    fn read<U>(field: Field<U>&, text: const u8[:], source: Occurrence) -> u8[>..] {
        let error = check_value(field.value, text);
        if error.len == 0 { supplied.push(source); }
        return error;
    }

    fn read_next<U>(field: Field<U>&, name: const u8[:]) -> u8[>..] {
        if is_flag(field.value) { return read(field, "true", Occurrence { name: name, index: i, flag: true }); }
        if i == argv.len { return "missing value"; }
        let error = read(field, argv[i], Occurrence { name: name, index: i });
        i += 1;
        return error;
    }

    let schema_error = validate(options);
    if schema_error.len > 0 { return result(), false, copy(schema_error); }
    var positional = 0;
    var end_options = false;
    while i < argv.len {
        let arg = argv[i];
        if !end_options && arg == "--" { end_options = true; i += 1; continue; }
        if !end_options && (arg == "--help" || arg == "-h") { return result(), true, ""; }
        let named = !end_options && starts_with(arg, "-") && arg != "-";
        if named { i += 1; }
        if named && !starts_with(arg, "--") {
            var cursor = 1;
            while cursor < arg.len {
                let short_name = arg[cursor..cursor + 1];
                if short_name == "h" { return result(), true, ""; }
                cursor += 1;
                var found = false;
                const for <Name, Access> in fields<T> {
                    let field = options.Access;
                    if !field.positional && field.short == short_name {
                        found = true;
                        let error = if !is_flag(field.value) && cursor < arg.len {
                            let value = arg[cursor..];
                            let source = Occurrence { name: Name, index: i - 1, offset: cursor };
                            cursor = arg.len;
                            read(field, value, source)
                        } else { read_next(field, Name) };
                        if error.len > 0 { return result(), false, str("-", short_name, ": ", error); }
                    }
                }
                if !found { return result(), false, str("unknown option: -", short_name); }
            }
            continue;
        }
        var found = false;
        var position = 0;
        const for <Name, Access> in fields<T> {
            let field = options.Access;
            let long_name = str("--", option_name(Name, field.long));
            let attached = named && starts_with(arg, str(long_name, "="));
            let matches = if field.positional {
                let selected = !named && position == positional;
                position += 1;
                selected
            } else { named && (arg == long_name || attached) };
            if matches {
                found = true;
                let error = if attached {
                    let source = Occurrence { name: Name, index: i - 1, offset: long_name.len + 1 };
                    read(field, arg[source.offset..], source)
                } else { read_next(field, Name) };
                if error.len > 0 {
                    let label = if field.positional { Name } else if attached { long_name } else { arg };
                    return result(), false, str(label, ": ", error);
                }
            }
        }
        if !found {
            return result(), false, str(if named { "unknown option: " } else { "unexpected argument: " }, arg);
        }
        if !named { positional += 1; }
    }
    const for <Name, Access> in fields<T> {
        let field = options.Access;
        var provided = false;
        for source in supplied { if source.name == Name { provided = true; } }
        if field.required && !provided {
            let label = if field.positional { Name } else { option_name(Name, field.long) };
            return result(), false, str(if field.positional { "missing required argument: " } else { "missing required option: --" }, label);
        }
    }
    return result(), false, "";
}

// Locations in argv let result arrays borrow the caller's bytes, not scratch storage.
struct Occurrence {
    name:   const u8[:],
    index:  i64,
    offset: i64  = 0,
    flag:   bool = false,
}

fn check_value(value: const u8[:], text: const u8[:]) -> u8[>..] { return ""; }
fn check_value(value: (const u8[:])[]&, text: const u8[:]) -> u8[>..] { return ""; }
fn check_value<T>(value: T&, text: const u8[:]) -> u8[>..] {
    var parsed = default<T>();
    return read_value(&parsed, text);
}

fn read_value(value: bool&, text: const u8[:]) -> u8[>..] {
    if text != "true" && text != "false" {
        return str("expected bool (true or false), got '", text, "'");
    }
    value = text == "true";
    return "";
}

fn read_value(value: i64&, text: const u8[:]) -> u8[>..] {
    let parsed, ok = parse_int(text);
    if !ok { return str("expected i64, got '", text, "'"); }
    value = parsed;
    return "";
}

fn read_value(value: const u8[:]&, text: const u8[:]) -> u8[>..] {
    value = text;
    return "";
}

fn read_value<T>(value: T&, text: const u8[:]) -> u8[>..] {
    const for <Name, Variant> in variants<T> {
        if text == Name { value = Variant; return ""; }
    }
    let label, choices = describe_value<T>(value);
    return str("expected one of [", choices, "], got '", text, "'");
}

// Display the value and its allowed choices, without enum type prefixes.
fn describe_value(value: bool) -> u8[>..], u8[>..] { return str(value), ""; }
fn describe_value(value: i64) -> u8[>..], u8[>..] { return str(value), ""; }
fn describe_value(value: const u8[:]) -> u8[>..], u8[>..] { return str(value), ""; }
fn describe_value(value: (const u8[:])[]&) -> u8[>..], u8[>..] { return str(value), ""; }
fn describe_value<T>(value: T) -> u8[>..], u8[>..] {
    var label:   u8[>..] = [];
    var choices: u8[>..] = [];
    const for <Name, Variant> in variants<T> {
        if choices.len > 0 { format(choices, ", "); }
        format(choices, Name);
        let candidate: T = Variant;
        if value == candidate { format(label, Name); }
    }
    return label, choices;
}

// Generate GNU-style help for your options struct.
// Use `help<Options>(program)` for declared defaults, or
// `help(program, defaults, description)` for configured defaults and an optional
// description. Pass the original defaults, not the parsed result.
//
// The text includes usage, positional arguments, option names, descriptions,
// required/repeatable markers, defaults, enum choices, and `-h`/`--help`. Option syntax
// supports zsh's `_gnu_generic` option-name completion.
// With array fields, use `help<Options>(program)`, `copy(defaults)`, or a fresh
// struct constructor.
//
// Call after parse requests help, so field settings have been validated.
// The returned text ends in a newline; write it to stdout without adding
// another one. This function does not print or exit.
//
// Using `Options` from the [example preamble](test/doc_preamble.goose):
//
// ```goose
// let argv = ["--help"];
// let options, help_requested, error = opts::parse<Options>(argv);
// assert(error == "" && help_requested);
// let text = opts::help<Options>("copy");
// assert(starts_with(text, "Usage: copy [OPTIONS] INPUT\n"));
// assert(find(text, "-c, --count=COUNT  Number of copies [default: 1]") >= 0);
// let enum_text = opts::help("convert", FormatOptions {}, "Choose an output format.");
// assert(find(enum_text, "[choices: json, plain_text, CSV] [default: plain_text]") >= 0);
// let defaults = IncludeOptions {};
// let repeated_text = opts::help("search", copy(defaults));
// assert(find(repeated_text, "-I, --include=INCLUDE  Search directory [repeatable] [default: []]") >= 0);
// ```
fn help<T>(program: const u8[:], defaults: T = T { .. }, description: const u8[:] = "") -> u8[>..] {
    var out = str("Usage: ", program, " [OPTIONS]");
    const for <Name, Access> in fields<T> {
        let field = defaults.Access;
        if field.required && !field.positional {
            format(out, " --", option_name(Name, field.long));
            if !is_flag(field.value) {
                var label = str(option_name(Name, field.long));
                to_upper(label);
                format(out, "=", label);
            }
        }
    }
    const for <Name, Access> in fields<T> {
        let field = defaults.Access;
        if field.positional {
            var label = str(Name);
            to_upper(label);
            if field.required { format(out, " ", label); }
            else { format(out, " [", label, "]"); }
        }
    }
    format(out, "\n");
    if description.len > 0 { format(out, "\n", description, "\n"); }
    var arguments: u8[>..] = [];
    var options:   u8[>..] = [];
    const for <Name, Access> in fields<T> {
        let field = defaults.Access;
        var label = str(if field.positional { Name } else { option_name(Name, field.long) });
        to_upper(label);
        var row = str("  ");
        if field.positional { format(row, label); }
        else {
            if field.short.len > 0 { format(row, "-", field.short, ", "); }
            format(row, "--", option_name(Name, field.long));
            // '=' tells zsh's _gnu_generic that this option consumes a value.
            if !is_flag(field.value) { format(row, "=", label); }
        }
        format(row, "  ");
        format_replaced(row, field.help, "\n", "\n    ");
        if is_repeated(field.value) { format(row, " [repeatable]"); }
        let value_label, choices = describe_value(field.value);
        if choices.len > 0 { format(row, " [choices: ", choices, "]"); }
        if field.required { format(row, " [required]"); }
        else { format(row, " [default: ", value_label, "]"); }
        format(row, "\n");
        if field.positional { arguments.append(row); }
        else { options.append(row); }
    }
    if arguments.len > 0 { format(out, "\nArguments:\n", arguments); }
    format(out, "\nOptions:\n", options, "  -h, --help  Show this help and exit\n");
    return out;
}
