#!/bin/bash
# Wrapper script to include local Perl modules for latexindent
export PERL5LIB="/Users/lukehassel/perl5/lib/perl5:$PERL5LIB"
/Library/TeX/texbin/latexindent "$@"
