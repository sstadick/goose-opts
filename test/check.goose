import std;
import goosopt from "..";

struct Options {
    name:    goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> { value: "default" },
    count:   goosopt::Field<i64>         = goosopt::Field<i64> { value: 7 },
    verbose: goosopt::Field<bool>        = goosopt::Field<bool> {},
}
struct Other { dry_run: goosopt::Field<bool>, limit: goosopt::Field<i64>, quiet: goosopt::Field<bool> }
struct Empty {}
struct Reserved { help: goosopt::Field<bool> = goosopt::Field<bool> {} }

fn check(argv: (const u8[:])[:], name: const u8[:], count: i64, verbose: bool, defaults: Options = Options {}) {
    let options, help_requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !help_requested);
    assert(options.name.value == name && options.count.value == count && options.verbose.value == verbose);
    assert(options.name.help == defaults.name.help && options.name.required == defaults.name.required);
    assert(options.name.long == defaults.name.long && options.name.short == defaults.name.short);
    assert(defaults.name.value == "default" && defaults.count.value == 7 && !defaults.verbose.value);
}

fn check_error<T>(argv: (const u8[:])[:], defaults: T, expected: const u8[:]) {
    let options, help_requested, error = goosopt::parse(argv, defaults);
    assert(error == expected && !help_requested);
}

fn check_presence(argv: (const u8[:])[:], name: bool, count: bool, verbose: bool, verbose_value: bool = true) {
    var defaults = Options {};
    assert(!defaults.name.provided && !defaults.count.provided && !defaults.verbose.provided);
    defaults.name.value = "";
    defaults.count.value = 0;
    defaults.verbose.value = true;
    defaults.name.short = "n";
    defaults.count.short = "c";
    defaults.verbose.short = "v";
    // Stale presence must not leak into this parse or mutate the caller.
    defaults.name.provided = true;
    defaults.count.provided = true;
    defaults.verbose.provided = true;
    let options, help_requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !help_requested);
    assert(options.name.value == "" && options.count.value == 0 && options.verbose.value == verbose_value);
    assert(options.name.provided == name && options.count.provided == count && options.verbose.provided == verbose);
    assert(defaults.name.provided && defaults.count.provided && defaults.verbose.provided);
}

fn main() {
    check_presence([], false, false, false);
    check_presence(["--count", "0"], false, true, false);
    check_presence(["--name="], true, false, false);
    check_presence(["--verbose"], false, false, true);
    check_presence(["--verbose=true"], false, false, true);
    check_presence(["--verbose=false"], false, false, true, false);
    check_presence(["-vvc0", "-n", ""], true, true, true);
    check_presence(["--count=1", "--count=0"], false, true, false);
    check([], "default", 7, false);
    check(["--count", "-23", "--verbose", "--name", "Ada Lovelace"], "Ada Lovelace", -23, true);
    check(["--name", "first", "--name", "", "--count", "2", "--count", "9", "--verbose", "--verbose"], "", 9, true);
    // Values consume exactly one token, including tokens that look like options.
    check(["--name", "--verbose"], "--verbose", 7, false);
    check(["--name", "--help"], "--help", 7, false);
    check(["--name=", "--count=-13"], "", -13, false);
    check(["--name=a=b", "--"], "a=b", 7, false);
    check_error(["--count"], Options {}, "--count: missing value");
    check_error(["--name"], Options {}, "--name: missing value");
    check(["--verbose=true", "--verbose=false"], "default", 7, false);
    check(["--verbose=false", "--verbose"], "default", 7, true);
    check_error(["--verbose", "false"], Options {}, "unexpected argument: false");
    for bad in ["", "True", "FALSE", "0", "1", "yes", "false ", "--help"] {
        let arg = str("--verbose=", bad);
        let argv: (const u8[:])[1] = [arg[..]];
        check_error(argv, Options {}, str("--verbose: expected bool (true or false), got '", bad, "'"));
    }
    check_error(["--count="], Options {}, "--count: expected i64, got ''");
    for bad in ["", "12x", "1.5", "9223372036854775808", "-9223372036854775809"] {
        check_error(["--count", bad], Options {}, str("--count: expected i64, got '", bad, "'"));
    }
    check(["--count", "9223372036854775807"], "default", 9223372036854775807, false);
    check(["--count", "-9223372036854775808"], "default", -9223372036854775807 - 1, false);
    for bad in ["--missing", "-v", "--counted=3"] {
        check_error([bad], Options {}, str("unknown option: ", bad));
    }
    check_error(["positional"], Options {}, "unexpected argument: positional");
    check_error(["--", "--help"], Options {}, "unexpected argument: --help");
    check_error(["--count", "42", "--missing", "--count", "99"], Options {}, "unknown option: --missing");

    // A different schema ensures names are reflected, not registered by hand.
    let argv = ["--limit", "11", "--dry_run"];
    let other, other_help, error = goosopt::parse<Other>(argv);
    assert(error == "" && !other_help && other.dry_run.value && other.limit.value == 11);
    let no_args: (const u8[:])[0] = [];
    let zero, zero_help, zero_error = goosopt::parse<Other>(no_args);
    assert(zero_error == "" && !zero_help && !zero.dry_run.value && zero.limit.value == 0);
    var flags = default<Other>();
    flags.dry_run.short = "d";
    flags.quiet.short = "q";
    flags.limit.short = "l";
    for bundle in ["-dq", "-qdl-6"] {
        let args = [bundle];
        let parsed, help_requested, error = goosopt::parse(args, flags);
        assert(error == "" && !help_requested && parsed.dry_run.value && parsed.quiet.value);
        assert(parsed.limit.value == (if bundle == "-dq" { 0 } else { -6 }));
    }
    let empty, empty_help, empty_error = goosopt::parse<Empty>(no_args);
    assert(empty_error == "" && !empty_help);
    check_error(["--name", "x"], Empty {}, "unknown option: --name");
    check_metadata();
    check_names();
    check_enums();
    check_repeated();
    print("goosopt checks passed");
}

struct Command {
    input:   goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> { required: true, positional: true },
    name:    goosopt::Field<const u8[:]> = goosopt::Field<const u8[:]> { value: "placeholder", required: true, help: "Display name" },
    count:   goosopt::Field<i64>         = goosopt::Field<i64> { value: 7, positional: true },
    verbose: goosopt::Field<bool>        = goosopt::Field<bool> {},
}

fn check_command(argv: (const u8[:])[:], input: const u8[:], name: const u8[:], count: i64, verbose: bool) {
    let defaults = Command {};
    let options, help_requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !help_requested);
    assert(options.input.value == input && options.name.value == name);
    assert(options.count.value == count && options.verbose.value == verbose);
    assert(options.input.positional && options.input.required && options.count.positional);
    assert(defaults.input.value == "" && defaults.name.value == "placeholder" && defaults.count.value == 7 && !defaults.verbose.value);
}

fn check_metadata() {
    check_command(["source", "--name", "Ada"], "source", "Ada", 7, false);
    check_command(["--name=Ada", "source", "--verbose", "12"], "source", "Ada", 12, true);
    check_command(["--name", "", "--", "--help", "-5"], "--help", "", -5, false);
    check_command(["", "--name=Ada"], "", "Ada", 7, false);
    check_command(["-", "--name", "Ada"], "-", "Ada", 7, false);
    check_error([], Command {}, "missing required argument: input");
    check_error(["source"], Command {}, "missing required option: --name");
    check_error(["source", "--name", "Ada", "oops"], Command {}, "count: expected i64, got 'oops'");
    check_error(["source", "--name", "Ada", "3", "extra"], Command {}, "unexpected argument: extra");
    check_error(["--input", "source"], Command {}, "unknown option: --input");
    check_error(["--name", "Ada", "source", "-5"], Command {}, "unknown option: -5");
    for flag in ["--help", "-h"] {
        let argv = [flag, "--unknown"];
        let options, help_requested, error = goosopt::parse<Command>(argv);
        assert(help_requested && error == "");
    }
    check_error(["--unknown", "--help"], Command {}, "unknown option: --unknown");
    check_error(["--name", "--help"], Command {}, "missing required argument: input");
    let text = goosopt::help<Command>("command");
    assert(starts_with(text, "Usage: command [OPTIONS] --name=NAME INPUT [COUNT]\n"));
    assert(find(text, "placeholder") == -1 && find(text, "[default: 7]") >= 0);

    var defaults = Options {};
    defaults.verbose.positional = true;
    check_error(["--help"], defaults, "boolean positional is not supported: verbose");
    defaults = Options {};
    defaults.name.positional = true;
    defaults.count.positional = true;
    defaults.count.required = true;
    check_error(["--help"], defaults, "required positional follows optional positional: count");
    defaults = Options {};
    defaults.count.required = true;
    defaults.count.provided = true;
    check_error([], defaults, "missing required option: --count");
    check(["--count", "0"], "default", 0, false, defaults);
    check_error([], Reserved {}, "reserved option name: --help");

    defaults = Options {};
    defaults.verbose.value = true;
    defaults.verbose.required = true;
    defaults.verbose.long = "enabled";
    check_error([], defaults, "missing required option: --enabled");
    let bool_argv = ["--enabled=false"];
    let disabled, disabled_help, disabled_error = goosopt::parse(bool_argv, defaults);
    assert(disabled_error == "" && !disabled_help && !disabled.verbose.value && disabled.verbose.provided);
    assert(defaults.verbose.value && !defaults.verbose.provided);

    // Positionals count as supplied even when empty or equal to a default.
    let argv = ["", "--name=", "7"];
    let parsed, help_requested, error = goosopt::parse<Command>(argv);
    assert(error == "" && !help_requested);
    assert(parsed.input.provided && parsed.name.provided && parsed.count.provided && !parsed.verbose.provided);
    let next_argv = ["source", "--name", "Ada"];
    let next, next_help, next_error = goosopt::parse(next_argv, parsed);
    assert(next_error == "" && !next_help && next.input.provided && next.name.provided);
    assert(next.count.value == 7 && !next.count.provided && !next.verbose.provided);
    assert(parsed.count.provided);
    check_error([], parsed, "missing required argument: input");
}

fn check_names() {
    var defaults = Options {};
    defaults.name.long = "output-file";
    defaults.name.short = "o";
    defaults.name.required = true;
    defaults.name.help = "Output path";
    defaults.count.short = "c";
    defaults.verbose.short = "v";
    check(["-o", "first", "-c", "-9", "-v"], "first", -9, true, defaults);
    check(["--output-file=a=b", "--count", "2"], "a=b", 2, false, defaults);
    check(["-o", "first", "--output-file", "last"], "last", 7, false, defaults);
    check(["--output-file=first", "-o", ""], "", 7, false, defaults);
    check(["-o", "--help"], "--help", 7, false, defaults);
    check(["-ovalue", "-c3"], "value", 3, false, defaults);
    check(["-vvc-9", "-olast"], "last", -9, true, defaults);
    check(["-vc", "12", "-ovalue"], "value", 12, true, defaults);
    check(["-ovc3"], "vc3", 7, false, defaults);
    check(["-o=value"], "=value", 7, false, defaults);
    check(["-vo--help"], "--help", 7, true, defaults);
    check(["-vo", "--"], "--", 7, true, defaults);
    check(["-vv", "--verbose=false", "-ovalue"], "value", 7, false, defaults);
    check(["--verbose=false", "-vovalue"], "value", 7, true, defaults);
    check(["-c3", "-c-4", "--count=5", "-ovalue"], "value", 5, false, defaults);
    check_error([], defaults, "missing required option: --output-file");
    check_error(["-vv"], defaults, "missing required option: --output-file");
    check_error(["-vc"], defaults, "-c: missing value");
    check_error(["-vc3v"], defaults, "-c: expected i64, got '3v'");
    check_error(["-c=3"], defaults, "-c: expected i64, got '=3'");
    check_error(["-c9223372036854775808"], defaults, "-c: expected i64, got '9223372036854775808'");
    check_error(["-vzh"], defaults, "unknown option: -z");
    check_error(["-ch"], defaults, "-c: expected i64, got 'h'");
    check_error(["-v=true"], defaults, "unknown option: -=");
    for flag in ["-vh", "-hv", "-vhz"] {
        let argv = [flag];
        let options, help_requested, error = goosopt::parse(argv, defaults);
        assert(error == "" && help_requested);
    }
    check_error(["-o"], defaults, "-o: missing value");
    check_error(["-c", "bad"], defaults, "-c: expected i64, got 'bad'");
    check_error(["--count=bad"], defaults, "--count: expected i64, got 'bad'");
    for bad in ["--name", "-O"] {
        check_error([bad], defaults, str("unknown option: ", bad));
    }
    check_error(["--", "-o"], defaults, "unexpected argument: -o");
    check_error(["--", "-vc3"], defaults, "unexpected argument: -vc3");
    let text = goosopt::help("named", defaults);
    assert(starts_with(text, "Usage: named [OPTIONS] --output-file=OUTPUT-FILE\n"));
    assert(find(text, "-o, --output-file=OUTPUT-FILE  Output path [required]") >= 0 && find(text, "--name") == -1);

    defaults = Options {};
    defaults.name.long = "count";
    check_error(["--help"], defaults, "duplicate long option: --count");
    defaults.name.long = "same";
    defaults.count.long = "same";
    check_error(["--help"], defaults, "duplicate long option: --same");
    defaults = Options {};
    defaults.name.short = "x";
    defaults.count.short = "x";
    check_error(["--help"], defaults, "duplicate short option: -x");
    defaults = Options {};
    defaults.name.long = "help";
    check_error(["--help"], defaults, "reserved option name: --help");
    defaults = Options {};
    defaults.name.short = "h";
    check_error(["--help"], defaults, "reserved option name: -h");
    defaults.name.positional = true;
    check_error(["--help"], defaults, "positional cannot have option names: name");
    defaults.name.short = "";
    defaults.name.long = "file";
    check_error(["--help"], defaults, "positional cannot have option names: name");
    defaults = Options {};
    for bad in ["--file", "a b", "a=b", "a,b", "a\nb", "é"] {
        defaults.name.long = bad;
        check_error(["--help"], defaults, str("invalid long option name: ", bad));
    }
    defaults = Options {};
    for bad in ["nn", "-n", "1", "=", "é"] {
        defaults.name.short = bad;
        check_error(["--help"], defaults, str("short option must be one ASCII letter: ", bad));
    }
    // Long and short names are separate namespaces, and short names are case-sensitive.
    defaults.name.short = "V";
    defaults.name.long = "v";
    defaults.verbose.short = "v";
    check(["--v", "long", "-V", "short", "-v"], "short", 7, true, defaults);
}

enum Format { json, plain_text, CSV }
enum Mode { slow, fast }
struct EnumOptions {
    mode: goosopt::Field<Mode> = goosopt::Field<Mode> { positional: true, required: true },
    output: goosopt::Field<Format> = goosopt::Field<Format> {
        value: Format.plain_text, long: "format", short: "f", help: "Output format",
    },
    verbose: goosopt::Field<bool> = goosopt::Field<bool> { short: "v" },
}

fn check_enum(argv: (const u8[:])[:], expected: Format, provided: bool = true, verbose: bool = false) {
    let defaults = EnumOptions {};
    let options, help_requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !help_requested);
    assert(options.output.value == expected && options.output.provided == provided);
    assert(options.mode.value == Mode.fast && options.mode.provided);
    assert(options.verbose.value == verbose);
    assert(defaults.output.value == Format.plain_text && !defaults.output.provided);
}

fn check_enums() {
    check_enum(["fast"], Format.plain_text, false);
    check_enum(["--format=json", "fast"], Format.json);
    check_enum(["fast", "--format", "CSV"], Format.CSV);
    check_enum(["-f", "plain_text", "fast"], Format.plain_text);
    check_enum(["-fCSV", "fast"], Format.CSV);
    check_enum(["-vfjson", "--", "fast"], Format.json, true, true);
    check_enum(["fast", "--format=json", "-fCSV"], Format.CSV);
    check_error(["fast", "--format"], EnumOptions {}, "--format: missing value");
    check_error(["fast", "-vf"], EnumOptions {}, "-f: missing value");
    for bad in ["", "JSON", "csv", "plain-text", "Format.json", "0", "json ", "--help"] {
        check_error(["fast", "--format", bad], EnumOptions {},
            str("--format: expected one of [json, plain_text, CSV], got '", bad, "'"));
    }
    check_error(["fast", "-fnope"], EnumOptions {}, "-f: expected one of [json, plain_text, CSV], got 'nope'");
    check_error(["FAST"], EnumOptions {}, "mode: expected one of [slow, fast], got 'FAST'");
    check_error([], EnumOptions {}, "missing required argument: mode");

    var defaults = EnumOptions {};
    defaults.output.required = true;
    defaults.output.provided = true;
    check_error(["fast"], defaults, "missing required option: --format");
    let argv = ["fast", "--format=plain_text"];
    let parsed, help_requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !help_requested && parsed.output.value == Format.plain_text && parsed.output.provided);
    check_error(["fast"], parsed, "missing required option: --format");
    let help_argv = ["--help"];
    let unused, requested, help_error = goosopt::parse(help_argv, defaults);
    assert(requested && help_error == "");
    let required_help = goosopt::help("enum", defaults);
    assert(find(required_help, "--format=FORMAT MODE\n") >= 0);
    assert(find(required_help, "[choices: json, plain_text, CSV] [required]") >= 0);
    let text = goosopt::help<EnumOptions>("enum");
    assert(find(text, "-f, --format=FORMAT  Output format [choices: json, plain_text, CSV] [default: plain_text]") >= 0);
    assert(find(text, "[choices: slow, fast] [required]") >= 0);
}

struct RepeatedOptions {
    paths: goosopt::Field<(const u8[:])[]> = goosopt::Field<(const u8[:])[]> {
        value: ["fallback", "base"], long: "include", short: "I", help: "Search paths",
    },
    count:   goosopt::Field<i64>             = goosopt::Field<i64> { value: 1, short: "c" },
    exclude: goosopt::Field<(const u8[:])[]> = goosopt::Field<(const u8[:])[]> { value: [], short: "X" },
    input:   goosopt::Field<const u8[:]>     = goosopt::Field<const u8[:]> { positional: true },
    verbose: goosopt::Field<bool>            = goosopt::Field<bool> { short: "v" },
}

fn check_repeat(argv: (const u8[:])[:], expected: (const u8[:])[:], provided: bool = true) {
    var defaults = RepeatedOptions {};
    defaults.paths.provided = true;
    let options, requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !requested);
    assert(options.paths.value.len == expected.len && options.paths.provided == provided);
    for i in expected.len { assert(options.paths.value[i] == expected[i]); }
    assert(options.exclude.value.len == 0 && !options.exclude.provided);
    assert(options.paths.long == "include" && options.paths.short == "I" && options.paths.help == "Search paths");
    assert(defaults.paths.value.len == 2 && defaults.paths.value[0] == "fallback" && defaults.paths.provided);
}

fn check_repeated() {
    check_repeat([], ["fallback", "base"], false);
    check_repeat(["--include", "src", "--include=tests", "-Ivendor"], ["src", "tests", "vendor"]);
    check_repeat(["--include="], [""]);
    check_repeat(["-I", "", "-I", "src", "-Isrc"], ["", "src", "src"]);
    check_repeat(["-vIone", "-I=two", "--include", "--help", "-I", "--"], ["one", "=two", "--help", "--"]);
    check_repeat(["--include", "a,b", "input.txt"], ["a,b"]);
    check_repeat(["--", "--include=literal"], ["fallback", "base"], false);
    check_error(["--include"], RepeatedOptions {}, "--include: missing value");
    check_error(["-vI"], RepeatedOptions {}, "-I: missing value");
    check_error(["--include=src", "one", "two"], RepeatedOptions {}, "unexpected argument: two");

    var defaults = RepeatedOptions {};
    let automatic_argv = ["-Isrc"];
    let automatic, automatic_help, automatic_error = goosopt::parse<RepeatedOptions>(automatic_argv);
    assert(automatic_error == "" && !automatic_help && automatic.paths.provided);
    assert(automatic.paths.value.len == 1 && automatic.paths.value[0] == "src");
    let omitted_argv: (const u8[:])[0] = [];
    let omitted, omitted_help, omitted_error = goosopt::parse<RepeatedOptions>(omitted_argv, copy(defaults));
    assert(omitted_error == "" && !omitted_help && !omitted.paths.provided);
    defaults.paths.value[0] = "changed";
    assert(omitted.paths.value.len == 2 && omitted.paths.value[0] == "fallback");
    defaults.paths.value[0] = "fallback";
    let argv = ["-Ione", "-Xbuild", "-c2", "--include=two", "--exclude=tmp", "-c9", "input.txt", "-v"];
    let parsed, requested, error = goosopt::parse(argv, defaults);
    assert(error == "" && !requested);
    assert(parsed.paths.value.len == 2 && parsed.paths.value[0] == "one" && parsed.paths.value[1] == "two");
    assert(parsed.exclude.value.len == 2 && parsed.exclude.value[0] == "build" && parsed.exclude.value[1] == "tmp");
    assert(parsed.paths.provided && parsed.exclude.provided && parsed.count.value == 9);
    assert(parsed.input.value == "input.txt" && parsed.verbose.value);
    let next_argv = ["--include=new"];
    let next, next_help, next_error = goosopt::parse(next_argv, parsed);
    assert(next_error == "" && !next_help && next.paths.value.len == 1 && next.paths.value[0] == "new");
    assert(next.paths.provided && !next.exclude.provided && next.exclude.value == parsed.exclude.value);
    assert(parsed.paths.value.len == 2 && defaults.paths.value[0] == "fallback");

    defaults.paths.required = true;
    defaults.paths.provided = true;
    check_error([], copy(defaults), "missing required option: --include");
    let empty_argv = ["--include="];
    let supplied, supplied_help, supplied_error = goosopt::parse(empty_argv, defaults);
    assert(supplied_error == "" && !supplied_help && supplied.paths.provided);
    assert(supplied.paths.value.len == 1 && supplied.paths.value[0] == "");
    check_error([], copy(supplied), "missing required option: --include");

    let text = goosopt::help<RepeatedOptions>("repeat");
    assert(find(text, "-I, --include=INCLUDE  Search paths [repeatable] [default: [\"fallback\", \"base\"]]") >= 0);
    assert(find(text, "-X, --exclude=EXCLUDE") >= 0 && find(text, "[repeatable] [default: []]") >= 0);
    defaults.paths.positional = true;
    defaults.paths.long = "";
    defaults.paths.short = "";
    check_error(["--help"], copy(defaults), "repeated positional is not supported: paths");

    var many: (const u8[:])[>..] = [];
    for i in 300 { many.push("--include=src"); }
    many.push("--include=last");
    let large_defaults = RepeatedOptions {};
    let large, large_help, large_error = goosopt::parse(many[..], large_defaults);
    assert(large_error == "" && !large_help && large.paths.value.len == 301);
    assert(large.paths.value[0] == "src" && large.paths.value[300] == "last");
}
