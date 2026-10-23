#!/usr/bin/perl
# Structural check for the one file allowed to build an ASWebAuthenticationSession (S5).
# Usage: guard-auth-session.pl <file>. Prints `<file>:<line>: <reason>` per violation, exits 1 if any.
#
# A small Swift lexer gives two views of the file, both the same length with newlines kept:
#   $c  comments blanked (strings kept)       -> where every mention is looked for
#   $b  comments and string bodies blanked    -> where code shape is checked
# It knows "..." / """...""" / #"..."# raw strings, \( ) interpolation (nested), // and nested /* */.
# Rules:
#   - every construction is `let X = ASWebAuthenticationSession(...) { ... }` and the very next
#     statement is `X.prefersEphemeralWebBrowserSession = true` (nothing after `true` but ; } or EOL);
#   - the only other allowed mentions are `extension ASWebAuthenticationSession: PasteAuthSession {}`
#     and a parameter annotation `name: ASWebAuthenticationSession)`; any other mention (typealias,
#     .init, .self, key path, string, a second assignment) fails;
#   - no .init / Self( / #if / KVC or runtime lookup in this file.
use strict;
use warnings;

my $file = shift or die "usage: $0 <file>\n";
open(my $fh, '<', $file) or die "$file: $!\n";
my $src = do { local $/; <$fh> };
close $fh;

my ($c, $b) = lex($src);
my @bad;
sub line_of { my ($pos) = @_; return 1 + (substr($src, 0, $pos) =~ tr/\n//); }
sub bad { my ($pos, $why) = @_; push @bad, sprintf("%s:%d: %s", $file, line_of($pos), $why); }

my $ID = qr/ASWebAuthenticationSession\w*/;
my $PE = qr/prefersEphemeralWebBrowserSession/;
my %ok_id;  # offsets of allowed ASWebAuthenticationSession mentions
my %ok_pe;  # offsets of allowed prefersEphemeralWebBrowserSession mentions

# Paired construction + assignment, checked on $b (strings blanked, so braces/parens balance).
my $OP = qr/[-+*\/%&|^!<>=.?~]/;
while ($b =~ /\blet\s+(\w+)\s*=\s*(ASWebAuthenticationSession)\s*
              (?<p>\((?:[^()]++|(?&p))*\))
              (?:[ \t]*(?<k>\{(?:[^{}]++|(?&k))*\}))?
              [ \t]*(?:;|\n)\s*
              \1\.($PE)[ \t]*=[ \t]*true\b
              (?=[ \t]*(?:;|\}|\n\s*+(?!$OP)|\z))/gx) {
    $ok_id{$-[2]} = 1;
    $ok_pe{$-[5]} = 1;
}
while ($b =~ /^[ \t]*extension\s+(ASWebAuthenticationSession)\s*:\s*PasteAuthSession\s*\{\s*\}[ \t]*$/mg) { $ok_id{$-[1]} = 1; }
while ($b =~ /\b\w+\s*:\s*(ASWebAuthenticationSession)\s*\)/g) { $ok_id{$-[1]} = 1; }

while ($c =~ /\b$ID/g) { $ok_id{$-[0]} or bad($-[0], "ASWebAuthenticationSession mention is not an allowed shape (let X = ASWebAuthenticationSession(...) then X.prefersEphemeralWebBrowserSession = true)"); }
while ($c =~ /$PE/g)  { $ok_pe{$-[0]} or bad($-[0], "prefersEphemeralWebBrowserSession used other than as the statement right after the construction"); }
while ($b =~ /(?<!\bsuper)(?<!\bself)\.\s*init\b/g) { bad($-[0], ".init is forbidden here (construct with ASWebAuthenticationSession(...))"); }
while ($b =~ /\bSelf\b/g) { bad($-[0], "Self is forbidden here"); }
while ($b =~ /^[ \t]*#(?:if|elseif|else)\b/mg) { bad($-[0], "conditional compilation is forbidden here"); }
while ($b =~ /\b(?:setValue|setValuesForKeys|perform|NSClassFromString|NSSelectorFromString|unsafeBitCast|objc_\w+|class_\w+|method_\w+)\b/g) {
    bad($-[0], "KVC / runtime lookup is forbidden here");
}

print "$_\n" for @bad;
exit(@bad ? 1 : 0);

sub lex {
    my ($s) = @_;
    my ($c, $b) = ('', '');
    my $n = length $s;
    # Frames: ['code', parens] (parens counts '(' inside an interpolation) or ['str', hashes, multi].
    my @st = (['code', -1]);
    my $i = 0;
    while ($i < $n) {
        my $f = $st[-1];
        my $ch = substr($s, $i, 1);
        if ($f->[0] eq 'code') {
            if (substr($s, $i, 2) eq '//') {
                my $j = index($s, "\n", $i); $j = $n if $j < 0;
                my $w = ' ' x ($j - $i); $c .= $w; $b .= $w; $i = $j; next;
            }
            if (substr($s, $i, 2) eq '/*') {
                my $d = 0; my $j = $i;
                while ($j < $n) {
                    if (substr($s, $j, 2) eq '/*') { $d++; $j += 2; next; }
                    if (substr($s, $j, 2) eq '*/') { $d--; $j += 2; last if $d == 0; next; }
                    $j++;
                }
                (my $w = substr($s, $i, $j - $i)) =~ s/[^\n]/ /g; $c .= $w; $b .= $w; $i = $j; next;
            }
            if (substr($s, $i) =~ /\A(#*)("""|")/) {
                my $open = $1 . $2;
                $c .= $open; $b .= $open; $i += length $open;
                push @st, ['str', length $1, $2 eq '"""']; next;
            }
            if ($f->[1] >= 0) {  # inside \( ... )
                if ($ch eq '(') { $f->[1]++; }
                elsif ($ch eq ')') {
                    if ($f->[1] == 0) { pop @st; $c .= ')'; $b .= ')'; $i++; next; }
                    $f->[1]--;
                }
            }
            $c .= $ch; $b .= $ch; $i++; next;
        }
        # string frame
        my ($h, $multi) = ($f->[1], $f->[2]);
        my $close = ($multi ? '"""' : '"') . ('#' x $h);
        if (substr($s, $i, length $close) eq $close) {
            $c .= $close; $b .= $close; $i += length $close; pop @st; next;
        }
        my $esc = '\\' . ('#' x $h);
        if (substr($s, $i, length $esc) eq $esc && $i + length($esc) < $n) {
            my $nx = substr($s, $i + length $esc, 1);
            if ($nx eq '(') {
                my $t = $esc . '(';
                $c .= $t; $b .= ' ' x (length($t) - 1) . '('; $i += length $t;
                push @st, ['code', 0]; next;
            }
            my $t = $esc . $nx;
            $c .= $t; (my $w = $t) =~ s/[^\n]/ /g; $b .= $w; $i += length $t; next;
        }
        $c .= $ch; $b .= ($ch eq "\n" ? "\n" : ' '); $i++;
    }
    return ($c, $b);
}
