import std;
import opts from "..";

struct Options {
    count: opts::Field<i64> = opts::Field<i64> { value: 7 },
}

// At -O2 this fixed schema proves check-free without annotating callees.
// At -O0 format_replaced retains checks: help is not generally check-free.
checkfree fn render_help() -> u8[>..] {
    return opts::help<Options>("demo");
}

fn main() {
    let text = render_help();
    assert(starts_with(text, "Usage: demo [OPTIONS]\n"));
    assert(find(text, "--count=COUNT   [default: 7]") >= 0);
    print("goose-opts checkfree help passed");
}
