// Expected compile failure: parsing arbitrary argv retains bounds checks.
import std;
import os;
import opts from "..";

struct Options {
    count: opts::Field<i64> = opts::Field<i64> { value: 7 },
}

checkfree fn parse_args<S>(argv: S[:]) {
    return opts::parse<Options>(argv);
}

fn main() {
    let argv = args();
    let options, requested, error = parse_args(argv[1..]);
    print(options.count.value, " ", requested, " ", error);
}
