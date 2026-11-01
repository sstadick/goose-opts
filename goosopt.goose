// Typed command-line options, positional arguments, and help text.
namespace goosopt;
import std;

// Declare an option or positional argument as a member of your options struct.
// T can be `bool`, `i64`, `const u8[:]`, or an enum with no variant payloads.
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
// ```goose
// let count = goosopt::Field<i64> { value: 3, short: "c", help: "Number of copies" };
// assert(count.value == 3 && count.short == "c" && !count.required);
// assert(!count.provided);
// let input = goosopt::Field<const u8[:]> { required: true, positional: true };
// assert(input.value == "" && input.required && input.positional);
// ```
//
// Using `enum Format { json, plain_text, CSV }` from the
// [example preamble](test/doc_preamble.goose):
//
// ```goose
// let output = goosopt::Field<Format> { value: Format.plain_text, short: "f" };
// assert(output.value == Format.plain_text && !output.provided);
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

fn option_name<T>(name: const u8[:], field: Field<T>) -> const u8[:] {
    return if field.long.len > 0 { field.long } else { name };
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

fn validate<T>(options: T) -> u8[>..] {
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
            if field.required && optional_positional {
                return str("required positional follows optional positional: ", Name);
            }
            if !field.required { optional_positional = true; }
        } else {
            let long_name = option_name(Name, field);
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
//
// - Integers, strings, and enums accept `--name VALUE`, `--name=VALUE`,
//   `-n VALUE`, or `-nVALUE`. Repeated options keep the last value.
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
// let options, help_requested, error = goosopt::parse<Options>(argv);
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
// let options, help_requested, error = goosopt::parse(argv, defaults);
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
// let options, help_requested, error = goosopt::parse<FormatOptions>(argv);
// assert(error == "" && !help_requested);
// assert(options.format.value == Format.CSV && options.format.provided);
// ```
fn parse<T, S>(argv: S[:], var options: T = default<T>()) -> T, bool, u8[>..] {
    const for <Name, Access> in fields<T> { options.Access.provided = false; }
    let schema_error = validate(options);
    if schema_error.len > 0 { return options, false, copy(schema_error); }
    var i = 0;
    var positional = 0;
    var end_options = false;
    while i < argv.len {
        let arg = argv[i];
        if !end_options && arg == "--" { end_options = true; i += 1; continue; }
        if !end_options && (arg == "--help" || arg == "-h") { return options, true, ""; }
        let named = !end_options && starts_with(arg, "-") && arg != "-";
        if named { i += 1; }
        if named && !starts_with(arg, "--") {
            var cursor = 1;
            while cursor < arg.len {
                let short_name = arg[cursor..cursor + 1];
                if short_name == "h" { return options, true, ""; }
                cursor += 1;
                var found = false;
                const for <Name, Access> in fields<T> {
                    let field = options.Access;
                    if !field.positional && field.short == short_name {
                        found = true;
                        let error = if !is_flag(field.value) && cursor < arg.len {
                            let value = arg[cursor..];
                            cursor = arg.len;
                            read_value(&options.Access.value, value)
                        } else { read_option(&options.Access.value, argv, i) };
                        if error.len > 0 { return options, false, str("-", short_name, ": ", error); }
                        options.Access.provided = true;
                    }
                }
                if !found { return options, false, str("unknown option: -", short_name); }
            }
            continue;
        }
        var found = false;
        var position = 0;
        const for <Name, Access> in fields<T> {
            let field = options.Access;
            let long_name = str("--", option_name(Name, field));
            let attached = named && starts_with(arg, str(long_name, "="));
            let matches = if field.positional {
                let selected = !named && position == positional;
                position += 1;
                selected
            } else { named && (arg == long_name || attached) };
            if matches {
                found = true;
                let error = if attached {
                    read_value(&options.Access.value, arg[long_name.len + 1..])
                } else { read_option(&options.Access.value, argv, i) };
                if error.len > 0 {
                    let label = if field.positional { Name } else if attached { long_name } else { arg };
                    return options, false, str(label, ": ", error);
                }
                options.Access.provided = true;
            }
        }
        if !found {
            return options, false, str(if named { "unknown option: " } else { "unexpected argument: " }, arg);
        }
        if !named { positional += 1; }
    }
    const for <Name, Access> in fields<T> {
        let field = options.Access;
        if field.required && !field.provided {
            let label = if field.positional { Name } else { option_name(Name, field) };
            return options, false, str(if field.positional { "missing required argument: " } else { "missing required option: --" }, label);
        }
    }
    return options, false, "";
}

fn read_option<T, S>(value: T&, argv: S[:], i: i64&) -> u8[>..] {
    let current: T = value;
    if is_flag(current) { return read_value(value, "true"); }
    if i == argv.len { return "missing value"; }
    let error = read_value(value, argv[i]);
    i += 1;
    return error;
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
// required markers, defaults, enum choices, and `-h`/`--help`. Option syntax
// supports zsh's `_gnu_generic` option-name completion.
//
// Call after parse requests help, so field settings have been validated.
// The returned text ends in a newline; write it to stdout without adding
// another one. This function does not print or exit.
//
// Using `Options` from the [example preamble](test/doc_preamble.goose):
//
// ```goose
// let argv = ["--help"];
// let options, help_requested, error = goosopt::parse<Options>(argv);
// assert(error == "" && help_requested);
// let text = goosopt::help<Options>("copy");
// assert(starts_with(text, "Usage: copy [OPTIONS] INPUT\n"));
// assert(find(text, "-c, --count=COUNT  Number of copies [default: 1]") >= 0);
// let enum_text = goosopt::help("convert", FormatOptions {}, "Choose an output format.");
// assert(find(enum_text, "[choices: json, plain_text, CSV] [default: plain_text]") >= 0);
// ```
fn help<T>(program: const u8[:], defaults: T = default<T>(), description: const u8[:] = "") -> u8[>..] {
    var out = str("Usage: ", program, " [OPTIONS]");
    const for <Name, Access> in fields<T> {
        let field = defaults.Access;
        if field.required && !field.positional {
            format(out, " --", option_name(Name, field));
            if !is_flag(field.value) {
                var label = str(option_name(Name, field));
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
        var label = str(if field.positional { Name } else { option_name(Name, field) });
        to_upper(label);
        var row = str("  ");
        if field.positional { format(row, label); }
        else {
            if field.short.len > 0 { format(row, "-", field.short, ", "); }
            format(row, "--", option_name(Name, field));
            // '=' tells zsh's _gnu_generic that this option consumes a value.
            if !is_flag(field.value) { format(row, "=", label); }
        }
        format(row, "  ");
        format_replaced(row, field.help, "\n", "\n    ");
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
