// Experimental struct-derived command-line options.
namespace goosopt;
import std;

// A CLI field's value and metadata, stored directly in the caller's options
// struct. T must be `bool`, `i64`, or `const u8[:]`. Read parsed data through
// `.value`; all other members remain unchanged by parsing.
//
// `value` defaults to the type's zero/empty value. `required` is explicit:
// when true, the user must supply the field even if `value` is initialized.
// Positionals consume one token in struct declaration order and cannot have
// long or short names. Required positionals must precede optional ones.
//
// An empty `long` uses the struct field name; otherwise it replaces that name
// on the CLI. Names contain ASCII letters, digits, underscores and hyphens,
// and cannot start with a hyphen. `short` is empty or one ASCII letter.
// `--help` and `-h` are reserved, and all option names must be unique within
// their respective long/short namespaces. `help` supplies descriptive text.
//
// ```goose
// let count = goosopt::Field<i64> { value: 3, short: "c", help: "Number of copies" };
// assert(count.value == 3 && count.short == "c" && !count.required);
// let input = goosopt::Field<const u8[:]> { required: true, positional: true };
// assert(input.value == "" && input.required && input.positional);
// ```
struct Field<T> {
    value:      T           = default<T>(),
    help:       const u8[:] = "",
    required:   bool        = false,
    positional: bool        = false,
    long:       const u8[:] = "",
    short:      const u8[:] = "",
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

// Parse arguments into a struct whose members are `Field<T>` wrappers.
// Call `parse<Options>(argv)` to use defaults declared on the options struct,
// or `parse(argv, defaults)` to supply a configured starting value.
// `argv` is an array/slice of strings and excludes the program name.
//
// Returns `options, help_requested, error`. Success means an empty error and
// false help flag. Discard the options on error or help; they may be partial.
// The caller's defaults and all field metadata are unchanged. String values
// borrow argument bytes: bind argv to a variable and keep its storage alive.
//
// Long values accept `--name VALUE` or `--name=VALUE`; short values require
// `-n VALUE`. Boolean flags set true and consume no value. Repeats use the
// last value. Bundles and attached short values are not supported.
// `--` ends option processing; a lone `-` is positional. A value token can
// itself be `--help`: help is recognized only where an option is expected.
// `-h`/`--help` bypass missing required fields, but not schema errors or an
// earlier parse error. The library never prints or exits.
//
// This example uses the `Options` struct in the
// [example preamble](test/doc_preamble.goose): a required input positional
// and a count option with default 1 and short name `c`.
//
// ```goose
// let argv = ["input.txt", "-c", "3"];
// let options, help_requested, error = goosopt::parse<Options>(argv);
// assert(error == "" && !help_requested);
// assert(options.input.value == "input.txt" && options.count.value == 3);
// let missing_args: (const u8[:])[0] = [];
// let missing, missing_help, missing_error = goosopt::parse<Options>(missing_args);
// assert(!missing_help && missing_error == "missing required argument: input");
// ```
fn parse<T, S>(argv: S[:], var options: T = default<T>()) -> T, bool, u8[>..] {
    let schema_error = validate(options);
    if schema_error.len > 0 { return options, false, copy(schema_error); }
    var seen: (const u8[:])[>..] = [];
    var i = 0;
    var positional = 0;
    var end_options = false;
    while i < argv.len {
        let arg = argv[i];
        if !end_options && arg == "--" { end_options = true; i += 1; continue; }
        if !end_options && (arg == "--help" || arg == "-h") { return options, true, ""; }
        let named = !end_options && starts_with(arg, "-") && arg != "-";
        if named { i += 1; }
        var found = false;
        var position = 0;
        const for <Name, Access> in fields<T> {
            let field = options.Access;
            let long_name = str("--", option_name(Name, field));
            let attached = named && starts_with(arg, str(long_name, "="));
            let short_match = field.short.len > 0 && arg == str("-", field.short);
            let matches = if field.positional {
                let selected = !named && position == positional;
                position += 1;
                selected
            } else { named && (arg == long_name || attached || short_match) };
            if matches {
                found = true;
                let error = if attached {
                    read_value(&options.Access.value, arg[long_name.len + 1..])
                } else { read_option(&options.Access.value, argv, &i) };
                if error.len > 0 {
                    let label = if field.positional { Name } else if attached { long_name } else { arg };
                    return options, false, str(label, ": ", error);
                }
                seen.push(Name);
            }
        }
        if !found {
            return options, false, str(if named { "unknown option: " } else { "unexpected argument: " }, arg);
        }
        if !named { positional += 1; }
    }
    const for <Name, Access> in fields<T> {
        let field = options.Access;
        if field.required && !contains(seen[..], Name) {
            let label = if field.positional { Name } else { option_name(Name, field) };
            return options, false, str(if field.positional { "missing required argument: " } else { "missing required option: --" }, label);
        }
    }
    return options, false, "";
}

fn read_option<S>(value: bool&, argv: S[:], i: i64&) -> u8[>..] {
    value = true;
    return "";
}

fn read_option<S>(value: i64&, argv: S[:], i: i64&) -> u8[>..] {
    if i == argv.len { return "missing value"; }
    let error = read_value(value, argv[i]);
    i += 1;
    return error;
}

fn read_option<S>(value: const u8[:]&, argv: S[:], i: i64&) -> u8[>..] {
    if i == argv.len { return "missing value"; }
    let error = read_value(value, argv[i]);
    i += 1;
    return error;
}

fn read_value(value: bool&, text: const u8[:]) -> u8[>..] {
    return "flag does not take a value";
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

// Generate GNU-style help from the wrappers in the options struct.
// Use `help<Options>(program)` for declared defaults, or pass the same defaults
// as parse. Use defaults, not the parsed result, to display original values.
// Includes Usage, positional arguments, option names, required markers,
// defaults, descriptions, and built-in help flags. Returns text ending in a
// newline; it never prints or exits. Call after parse reports help_requested
// so invalid field configurations have already been rejected.
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
        if field.required { format(row, " [required]"); }
        else { format(row, " [default: ", field.value, "]"); }
        format(row, "\n");
        if field.positional { arguments.append(row); }
        else { options.append(row); }
    }
    if arguments.len > 0 { format(out, "\nArguments:\n", arguments); }
    format(out, "\nOptions:\n", options, "  -h, --help  Show this help and exit\n");
    return out;
}
