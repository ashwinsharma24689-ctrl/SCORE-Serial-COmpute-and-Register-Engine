`timescale 1ns/1ps

module SIPO_reset_stress_tb;

parameter BCLK_PERIOD = 10;

reg  reset_n;
reg  data_tx;
reg  baud_clk;

wire        active_flag;
wire        recieved_flag;
wire [10:0] data_parll;

integer pass_count = 0;
integer fail_count = 0;

SIPO DUT (
    .reset_n       (reset_n),
    .data_tx       (data_tx),
    .baud_clk      (baud_clk),
    .active_flag   (active_flag),
    .recieved_flag (recieved_flag),
    .data_parll    (data_parll)
);

always #(BCLK_PERIOD/2) baud_clk = ~baud_clk;

initial begin
    #100_000;
    $display("TIMEOUT: SIPO_reset_stress_tb did not complete in time");
    $finish;
end

task check(input cond, input [8*70-1:0] msg);
begin
    if (cond) begin
        pass_count = pass_count + 1;
        $display("PASS  %0s", msg);
    end
    else begin
        fail_count = fail_count + 1;
        $display("FAIL  %0s", msg);
    end
end
endtask

// Forces the FSM into a specific non-IDLE configuration (mimicking "reset
// happens mid-frame"), releases the force so the values are ordinary
// register contents (not still driven by force) before reset fires, then
// asserts reset_n at a controlled delay relative to the last baud_clk edge
// -- sweeping that phase is what actually stresses the timing window the
// original bug depended on.
task stress_reset(input [1:0] forced_state, input [3:0] forced_stop_count,
                   input [3:0] forced_frame_counter, input real delay_before_reset,
                   input [8*20-1:0] label);
begin
    reset_n = 1'b1;
    @(posedge baud_clk);

    force DUT.next_state    = forced_state;
    force DUT.stop_count    = forced_stop_count;
    force DUT.frame_counter = forced_frame_counter;
    #1;
    release DUT.next_state;
    release DUT.stop_count;
    release DUT.frame_counter;

    #delay_before_reset;
    reset_n = 1'b0;
    #1;

    check(DUT.next_state    === 2'b00, {"[", label, "] reset forces next_state to IDLE immediately"});
    check(DUT.stop_count    === 4'd0,  {"[", label, "] reset clears stop_count immediately"});
    check(DUT.frame_counter === 4'd0,  {"[", label, "] reset clears frame_counter immediately"});
    check(DUT.temp          === 11'h7FF, {"[", label, "] reset clears temp to all-ones immediately"});

    // Confirm IDLE holds (or correctly proceeds only per data_tx) on the
    // very next active edge too -- the old bug's failure mode could still
    // let stale logic creep back in one edge later.
    @(posedge baud_clk);
    #1;
    if (data_tx == 1'b1)
        check(DUT.next_state === 2'b00, {"[", label, "] IDLE holds on next edge while data_tx stays high"});
    else
        check(DUT.next_state === 2'b01, {"[", label, "] correctly proceeds to CENTER on next edge when data_tx is low"});

    reset_n = 1'b1;
    repeat (3) @(posedge baud_clk);
end
endtask

initial begin
    baud_clk = 1'b0;
    reset_n  = 1'b0;
    data_tx  = 1'b1; // idle-high

    repeat (3) @(posedge baud_clk);
    reset_n = 1'b1;
    repeat (3) @(posedge baud_clk);

    // Sweep both the forced non-IDLE state and the phase of reset relative
    // to baud_clk, covering the timing window the original race depended on.
    stress_reset(2'b01, 4'd3,  4'd0, 1.0, "CENTER early ");
    stress_reset(2'b01, 4'd3,  4'd0, 8.0, "CENTER late  ");
    stress_reset(2'b11, 4'd10, 4'd5, 2.0, "FRAME mid    ");
    stress_reset(2'b11, 4'd10, 4'd5, 9.0, "FRAME late   ");
    stress_reset(2'b10, 4'd0,  4'd6, 4.0, "GET mid      ");
    stress_reset(2'b11, 4'd14, 4'd9, 0.5, "FRAME near-tx");

    $display("=== SIPO_reset_stress_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

endmodule
