# =============================================================================
# bd_patch_template.tcl -- Vivado Block Design incremental patch skeleton
#
# Copy this file and edit ONLY the section marked "2. THE ACTUAL PATCH".
# Do not remove the helpers, the guards, or the final status check.
#
# WHY THIS STRUCTURE (learned the hard way -- see skill/pitfalls/block-design-traps.md)
#
#   1) NEVER disconnect a SOURCE pin to "reconnect" it.
#      A helper like  reconnect(a,b) { disconnect a; disconnect b; connect a b; }
#      looks idempotent but SEVERS the whole net when 'a' is a clock/reset source
#      that already drives many loads. Symptom:
#          ERROR: [BD 41-758] The following clock pins are not connected to a valid clock source
#      To TAP an existing signal, ONLY ADD the new pin.
#
#   2) A BD pin's NAME is its LOCAL name (e.g. "probe3"), NOT a path.
#      Never use it to look up a net. Pass the PIN OBJECT instead:
#          get_bd_nets -of_objects $pinobj
#      Otherwise the lookup silently returns empty and the patch does nothing.
#
#   3) validate_bd_design MUST pass before save_bd_design. A failed validate
#      protects you: the on-disk design is left untouched. Never force-save.
#
#   4) ASCII ONLY. On zh-CN Windows, Vivado reads .tcl as GBK; non-ASCII bytes
#      can swallow a quote and produce a brace error somewhere unrelated.
#
# Verified on xc7z020 / Vivado 2023.1.
# =============================================================================

# ------------------------------ 0. Preconditions ---------------------------
if {[current_project -quiet] eq ""} {
    error "No project open. Open the project first (open_project <path>.xpr)."
}
puts "Project: [current_project]"

if {[get_bd_designs -quiet] eq ""} {
    set bdfiles [get_files -quiet *.bd]
    if {[llength $bdfiles] == 0} { error "No .bd file found in this project." }
    set target [lindex $bdfiles 0]
    puts "No BD open. Opening: $target"
    open_bd_design $target
}
puts "Active BD: [get_bd_designs]"

# ------------------------------ 1. Helpers ---------------------------------
proc net_of_pin_obj {pinobj} {
    set net [get_bd_nets -quiet -of_objects $pinobj]
    if {[llength $net] == 0} { return "" }
    return [get_property NAME $net]
}

proc net_of_pin_path {path} {
    set pin [get_bd_pins -quiet $path]
    if {[llength $pin] == 0} { return "NOT_FOUND_PIN" }
    set n [net_of_pin_obj $pin]
    if {$n eq ""} { return "" }
    return $n
}

# Unpin a SINGLE DESTINATION pin. Never call this on a source pin.
proc unpin_path {path} {
    set pin [get_bd_pins -quiet $path]
    if {[llength $pin] == 0} { puts "  WARN: pin not found: $path"; return 0 }
    set net [get_bd_nets -quiet -of_objects $pin]
    if {[llength $net] == 0} { puts "  already unconnected: $path"; return 0 }
    set nname [get_property NAME $net]
    if {[catch {disconnect_bd_net $net $pin} err]} {
        disconnect_bd_net -net $net $pin
    }
    puts "  Disconnected: $path   (was on net: $nname)"
    return 1
}

# Connect ONLY if the destination pin is free (idempotent).
proc connect_if_free {src dst} {
    set dpin [get_bd_pins -quiet $dst]
    if {[llength $dpin] == 0} { puts "  WARN: pin not found: $dst"; return 0 }
    set existing [get_bd_nets -quiet -of_objects $dpin]
    if {[llength $existing] > 0} {
        puts "  already connected: $dst  (net: [get_property NAME $existing])"
        return 0
    }
    if {[catch {connect_bd_net [get_bd_pins $src] $dpin} err]} {
        puts "  WARN: connect failed: $src -> $dst ($err)"
        return 0
    }
    puts "  Connected: $src -> $dst"
    return 1
}

proc ensure_cell {vlnv name} {
    if {[get_bd_cells -quiet $name] eq ""} {
        create_bd_cell -type ip -vlnv $vlnv $name
        puts "  Created $name"
    } else {
        puts "  $name already exists - reusing"
    }
}

# ------------------------------ 2. THE ACTUAL PATCH ------------------------
# Edit everything between here and "3. Self-check".
# Every lookup must print its result; empty results must print NOT FOUND.

puts "--- 2. patch: describe what this does ---"

# EXAMPLE A: create an IP cell idempotently
#   ensure_cell xilinx.com:ip:axi_gpio:2.0 axi_gpio_new

# EXAMPLE B: tap an existing clock (ADD a load -- never remove one)
#   connect_if_free processing_system7_0/FCLK_CLK0 axi_gpio_new/s_axi_aclk

# EXAMPLE C: route an AXI master port to a new slave (peripheral is the intercon)
#   connect_if_free axi_gpio_new/S_AXI axi_ps_periph/M05_AXI
#   connect_if_free processing_system7_0/FCLK_CLK0 axi_ps_periph/M05_ACLK
#   connect_if_free rst_ps7_100M/peripheral_aresetn axi_ps_periph/M05_ARESETN
#   NOTE: after widening an interconnect, the NEW clock/reset pins MUST also be
#         connected, or you get [BD 41-758].

# EXAMPLE D: replace a data source into an existing consumer
#   unpin_path axi_vdma_0/s_axis_s2mm_tdata     ;# destination only
#   ...

puts "--- 2. patch done ---"

# ------------------------------ 3. Self-check ------------------------------
puts "--- 3. self-check ---"

# Example: assert an expected object count. Fail loudly if it does not match.
# set found [get_bd_cells -quiet -filter {VLNV =~ "*:ip:axi_gpio:*"}]
# puts "axi_gpio cells: [llength $found] -> [get_property NAME $found]"
# if {[llength $found] != 2} { puts "  WARN: expected 2 axi_gpio cells" }

# ------------------------------ 4. Guards before saving --------------------
puts "--- 4. guards: critical nets must still exist ---"
set guard_paths {}
foreach c [get_bd_cells -quiet -filter {VLNV =~ "*:processing_system7:*"}] {
    foreach clk {FCLK_CLK0 FCLK_CLK1} {
        set pp [get_bd_pins -quiet "[get_property NAME $c]/$clk"]
        if {$pp ne ""} { lappend guard_paths "[get_property NAME $c]/$clk" }
    }
}
set guard_failed 0
foreach g $guard_paths {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet $g]]
    puts "    $g  nets=[llength $n]"
    if {[llength $n] == 0} { puts "    GUARD FAILED: $g has no net"; set guard_failed 1 }
}
if {$guard_failed} { error "GUARD FAILED: a shared clock net was severed. NOT saving." }

# ------------------------------ 5. Final state -----------------------------
if {[catch {validate_bd_design} verr]} {
    puts "FAILED: validate_bd_design rejected the design."
    puts "        NOT saved. Fix the errors above and re-run."
    puts "        reason: $verr"
} else {
    save_bd_design
    puts "DONE: BD validated and saved."
    puts "Next: reset_run synth_1 -> launch_runs impl_1 -to_step write_bitstream"
    puts "      -> write_hw_platform -fixed -include_bit -> update Vitis platform"
}
