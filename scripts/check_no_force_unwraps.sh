#!/usr/bin/env bash
# Fails if production Swift code contains `!` force unwraps, `try!`, `as!` or implicitly
# unwrapped optionals. Works without SwiftLint so CI can always run it.
# String literals and comments are stripped first so "Done!" or "// wow!" do not trip it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="${1:-$ROOT/TaskManager}"

violations=$(find "$SOURCE_DIR" -name '*.swift' -print0 | xargs -0 perl -ne '
    our ($in_block, $in_multiline);
    my $line = $_;

    # Multi-line string literals: skip their body lines entirely.
    my $fences = () = $line =~ /"""/g;
    if ($in_multiline) {
        $in_multiline = 0 if $fences % 2;
        goto NEXT;
    }
    if ($fences % 2) { $in_multiline = 1; $line =~ s{""".*$}{}; }

    # String literals: drop the text but keep \( ... \) interpolations, which are code.
    my $interp = qr/\\(\((?:[^()]++|(?1))*\))/;
    $line =~ s{"((?:[^"\\]|\\.)*)"}{ join(" ", $1 =~ /$interp/g) }ge;

    # Comments.
    if ($in_block) {
        if ($line =~ s{^.*?\*/}{}) { $in_block = 0 } else { goto NEXT }
    }
    $line =~ s{/\*.*?\*/}{}g;
    $line =~ s{//.*$}{};
    $in_block = 1 if $line =~ s{/\*.*$}{};

    # An identifier, ) or ] immediately followed by ! that is not part of !=
    print "$ARGV:$.: $_" if $line =~ /[A-Za-z0-9_)\]]!(?!=)/;

    NEXT:
    if (eof) { close ARGV; $in_block = 0; $in_multiline = 0; }   # reset $. and state per file
' || true)

if [[ -n "$violations" ]]; then
    echo "error: force unwrap, try! or as! found in production code:" >&2
    echo "$violations" >&2
    exit 1
fi

echo "check_no_force_unwraps: OK"
