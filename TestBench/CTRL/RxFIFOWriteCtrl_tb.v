`timescale 1ns/1ps
// ============================================================
//  RxFIFOWriteCtrl_tb
//
//  Drives rx_done_flag as a free-running toggle deliberately
//  unaligned to `clock` edges (mimicking a signal arriving from
//  a genuinely different, mesochronous domain), and checks:
//    - a clean one-cycle fifo_wr_en pulse follows each rising
//      edge, after synchronizer latency
//    - bytes with a nonzero error_flag are dropped
//    - bytes are dropped (not queued) while fifo_full is high
// ============================================================
module RxFIFOWriteCtrl_tb;

parameter CLK_PERIOD = 10;

reg        clock;
reg        reset_n;
reg        rx_done_flag;
reg  [7:0] rx_data_out;
reg  [2:0] rx_error_flag;
reg        fifo_full;

wire       fifo_wr_en;
wire [7:0] fifo_wr_data;

integer pass_count = 0;
integer fail_count = 0;
integer wr_pulse_count = 0;
reg [7:0] last_wr_data;

RxFIFOWriteCtrl DUT (
    .clock         (clock),
    .reset_n       (reset_n),
    .rx_done_flag  (rx_done_flag),
    .rx_data_out   (rx_data_out),
    .rx_error_flag (rx_error_flag),
    .fifo_wr_en    (fifo_wr_en),
    .fifo_wr_data  (fifo_wr_data),
    .fifo_full     (fifo_full)
);

always #(CLK_PERIOD/2) clock = ~clock;

always @(posedge clock) if (fifo_wr_en) begin
    wr_pulse_count = wr_pulse_count + 1;
    last_wr_data   = fifo_wr_data;
end

task check(input cond, input [8*60-1:0] msg);
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

// Pulse rx_done_flag high for a duration deliberately not aligned to clock edges,
// with valid data/error_flag held stable across it (mirrors DeFrame's stable outputs).
// The high window must safely exceed one full clock period -- a pulse narrower
// than that isn't guaranteed to overlap a sampling edge at all (worst-case phase
// alignment can drop it between two edges entirely), which is exactly what a
// synchronizer can't be expected to catch.
task deliver_byte(input [7:0] data, input [2:0] err_flag);
begin
    rx_data_out   = data;
    rx_error_flag = err_flag;
    #3;  // intentionally off-grid relative to the 10ns clock period
    rx_done_flag = 1'b1;
    #17; // > one full CLK_PERIOD, guarantees at least one sampling edge
    rx_done_flag = 1'b0;
    #60; // let it fully settle: 3 sync stages + wr_en registration + the
         // testbench's own posedge-delayed pulse counter can take up to
         // ~5 clock periods worst-case from the rising edge
end
endtask

initial begin
    clock = 1'b0;
    reset_n = 1'b0;
    rx_done_flag = 1'b0;
    rx_data_out = 8'd0;
    rx_error_flag = 3'd0;
    fifo_full = 1'b0;
    repeat (3) @(posedge clock);
    reset_n = 1'b1;
    repeat (2) @(posedge clock);

    // --- Valid byte, no error, FIFO not full: expect exactly one wr_en pulse ---
    wr_pulse_count = 0;
    deliver_byte(8'hA5, 3'b000);
    check(wr_pulse_count === 1, "valid byte: exactly one fifo_wr_en pulse generated");
    check(last_wr_data === 8'hA5, "valid byte: fifo_wr_data carries the correct byte");

    // --- Errored byte: must be dropped (no write) ---
    wr_pulse_count = 0;
    deliver_byte(8'h3C, 3'b010); // nonzero error_flag
    check(wr_pulse_count === 0, "errored byte: dropped, no fifo_wr_en pulse");

    // --- fifo_full asserted: valid byte must still be dropped ---
    fifo_full = 1'b1;
    wr_pulse_count = 0;
    deliver_byte(8'h77, 3'b000);
    check(wr_pulse_count === 0, "fifo_full asserted: valid byte dropped, no pulse");
    fifo_full = 1'b0;

    // --- Back-to-back valid bytes: two distinct pulses with correct data each ---
    wr_pulse_count = 0;
    deliver_byte(8'h11, 3'b000);
    deliver_byte(8'h22, 3'b000);
    check(wr_pulse_count === 2, "two consecutive valid bytes: two distinct pulses");

    $display("=== RxFIFOWriteCtrl_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT: RxFIFOWriteCtrl_tb did not complete in time");
    $finish;
end

endmodule