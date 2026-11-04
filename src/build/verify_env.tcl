# ============================================================================
# verify_env.tcl -- FIRST command a judge should run. Says what is missing
#                  instead of letting a build fail 20 minutes later.
#
#   usage:  vivado -mode batch -source src/build/verify_env.tcl
#   exit 0 = every input this repository expects is reachable
#   exit 1 = at least one input is missing (each one is printed by name)
#
# It only inspects the filesystem; it does not open a project or run synthesis,
# so it is safe to run anywhere and finishes in seconds.
# ASCII ONLY -- Vivado reads .tcl as GBK on a Chinese Windows console.
# ============================================================================
set ROOT [file normalize [file join [file dirname [info script]] .. ..]]

proc ENV {name def} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $def
}
proc RESOLVE {p base} {
    if {[file pathtype $p] eq "absolute"} { return $p }
    return [file join $base $p]
}

set XPR    [RESOLVE [ENV TRUSTSCOPE_XPR    [file join $ROOT hw two_fft "two FFT.xpr"]] $ROOT]
set XSA    [RESOLVE [ENV TRUSTSCOPE_XSA    [file join $ROOT src build FFT.xsa]]      $ROOT]
set SRCD   [RESOLVE [ENV TRUSTSCOPE_RTL    [file join $ROOT src rtl]]                $ROOT]
set IPREPO [RESOLVE [ENV TRUSTSCOPE_IPREPO [file join $ROOT src hls hls_proj sol1 impl ip]] $ROOT]
set BDTCL  [file join $ROOT src build bd design_1_bd.tcl]
set XDC    [file join $ROOT src two_fft.xdc]

puts "=========== verify_env ==========="
puts "root    = $ROOT"
puts "vivado  = [version -short]"
puts "tcl     = [info patchlevel]"

set bad 0
proc CHK {label path kind required} {
    global bad
    set ok 0
    if {$kind eq "file"} {
        set ok [file exists $path]
    } else {
        set ok [file isdirectory $path]
    }
    if {$ok} {
        puts "  OK       $label -> $path"
    } else {
        if {$required} {
            puts "  MISSING  $label -> $path   (required)"
            incr bad
        } else {
            puts "  absent   $label -> $path   (optional)"
        }
    }
}

# required to run batch_build.tcl / cnn_build.tcl at all
CHK "Vivado project (.xpr)" $XPR file 1
CHK "module_ref RTL dir"    $SRCD dir  1
# shipped in the repository, so their absence means the clone is broken
CHK "pin constraints"       $XDC  file 1
CHK "block design tcl"      $BDTCL file 1
# outputs / intermediate artefacts: absence is normal on a fresh clone
CHK "XSA"                   $XSA  file 0
CHK "packed CNN IP"         $IPREPO dir 0

puts "---"
if {$bad == 0} {
    puts "RESULT: PASS -- all required inputs reachable"
    exit 0
} else {
    puts "RESULT: FAIL -- $bad required input(s) missing"
    puts "The .xpr and the module_ref .v sources are NOT distributed with this"
    puts "repository (vendor board files + generated IP are not redistributable)."
    puts "Rebuild the block design from src/build/bd/design_1_bd.tcl, add the RTL,"
    puts "then export the XSA -- see src/build/README.md."
    exit 1
}
