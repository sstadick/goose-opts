#!/usr/bin/env python3
"""Check goosopt with TinyCC and a native C compiler, using a fresh Goose cache."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", default="goose")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--zsh", help="also require the interactive _gnu_generic completion test")
    args = parser.parse_args()
    goose = shutil.which(args.goose)
    cc = shutil.which(args.cc)
    zsh = shutil.which(args.zsh or "zsh")
    if not goose or not cc:
        parser.error("both --goose and --cc must name available executables")
    if args.zsh and not zsh:
        parser.error("--zsh must name an available executable")
    goose, cc = str(Path(goose).resolve()), str(Path(cc).resolve())
    if zsh:
        zsh = str(Path(zsh).resolve())
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="goosopt-") as tmp:
        out = Path(tmp)
        env = dict(os.environ, GOOSE_HOME=str(out / "home"))

        def run(command, stdout=None, stderr=None, code=0):
            result = subprocess.run([str(x) for x in command], cwd=out, env=env,
                                    capture_output=True, text=True, timeout=180)
            if (result.returncode != code
                    or (stdout is not None and result.stdout != stdout)
                    or (stderr is not None and result.stderr != stderr)):
                raise RuntimeError(f"{command}\nexit: {result.returncode}\n"
                                   f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}")
            return result

        checks = root / "test" / "check.goose"
        for level in (0, 2):
            run([goose, "run", "--debug", f"-O{level}", checks], "goosopt checks passed\n")
            print(f"PASS TinyCC -O{level}", flush=True)
        suffix = ".exe" if os.name == "nt" else ""
        native = out / ("check" + suffix)
        run([goose, "build", "--debug", "--cc", cc, "-o", native, checks])
        run([native], "goosopt checks passed\n", "")
        print("PASS native parser checks", flush=True)

        example = root / "examples" / "basic.goose"
        binary = out / ("basic" + suffix)
        run([goose, "build", "--cc", cc, "-o", binary, example])
        for command in ([goose, "run", example, "--"], [binary]):
            run(command, stdout="", stderr="missing required argument: input\n", code=2)
            run([*command, "input.txt"], stdout="", stderr="missing required option: --name\n", code=2)
            run([*command, "input.txt", "--name", "Ada Lovelace"], "input.txt Ada Lovelace 1 false Format.json\n", "")
            run([*command, "--name=Ada Lovelace", "input.txt", "--count=-3", "--verbose"],
                "input.txt Ada Lovelace -3 true Format.json\n", "")
            run([*command, "input.txt", "-n", "Ada", "-c", "-7", "-v"],
                "input.txt Ada -7 true Format.json\n", "")
            run([*command, "-vc-3", "input.txt", "-nAda"], "input.txt Ada -3 true Format.json\n", "")
            run([*command, "-vn--help", "-c3", "--", "-vc9"], "-vc9 --help 3 true Format.json\n", "")
            run([*command, "input.txt", "-nAda", "--verbose=true", "--verbose=false"],
                "input.txt Ada 1 false Format.json\n", "")
            run([*command, "--verbose", "false", "-nAda"], "false Ada 1 true Format.json\n", "")
            run([*command, "-nAda", "--", "--verbose=false"], "--verbose=false Ada 1 false Format.json\n", "")
            run([*command, "--verbose=False"], stdout="",
                stderr="--verbose: expected bool (true or false), got 'False'\n", code=2)
            run([*command, "input.txt", "-nAda", "--format=plain_text"],
                "input.txt Ada 1 false Format.plain_text\n", "")
            run([*command, "input.txt", "-nAda", "-vfCSV"], "input.txt Ada 1 true Format.CSV\n", "")
            run([*command, "--format=csv"], stdout="",
                stderr="--format: expected one of [json, plain_text, CSV], got 'csv'\n", code=2)
            run([*command, "-vc"], stdout="", stderr="-c: missing value\n", code=2)
            run([*command, "-vzh"], stdout="", stderr="unknown option: -z\n", code=2)
            run([*command, "--name", "--help", "--", "-file"], "-file --help 1 false Format.json\n", "")
            run([*command, "--count"], stdout="", stderr="--count: missing value\n", code=2)
            run([*command, "-n"], stdout="", stderr="-n: missing value\n", code=2)
            run([*command, "--count", "oops"],
                stdout="", stderr="--count: expected i64, got 'oops'\n", code=2)
            run([*command, "--unknown"], stdout="", stderr="unknown option: --unknown\n", code=2)
            run([*command, "--display_name=Ada"], stdout="",
                stderr="unknown option: --display_name=Ada\n", code=2)
            help_text = run([*command, "--help"], stderr="").stdout
            assert help_text.startswith("Usage: basic [OPTIONS] --name=NAME INPUT\n"), help_text
            for text in ("Input file [required]", "-n, --name=NAME  Name to display [required]",
                         "-c, --count=COUNT  Number of copies [default: 1]",
                         "-f, --format=FORMAT  Output format [choices: json, plain_text, CSV] [default: json]",
                         "-v, --verbose  Enable verbose output [default: false]", "-h, --help"):
                assert text in help_text, help_text
            assert all(text not in help_text for text in ("--input", "--verbose=", "--display_name")), help_text
            run([*command, "-h"], stdout=help_text, stderr="")
            run([*command, "-vhz"], stdout=help_text, stderr="")
        print("PASS example CLI (TinyCC and native)", flush=True)
        if zsh:
            run([zsh, root / "test" / "completion.zsh", binary, zsh],
                "PASS zsh _gnu_generic completion\n", "")
            print("PASS zsh _gnu_generic completion", flush=True)
        else:
            print("SKIP zsh completion (install zsh or pass --zsh)", flush=True)


if __name__ == "__main__":
    main()
