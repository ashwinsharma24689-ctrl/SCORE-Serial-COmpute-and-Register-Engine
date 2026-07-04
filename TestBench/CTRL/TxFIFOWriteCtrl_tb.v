`timescale 1ns/1ps
// ============================================================
//  TxFIFOWriteCtrl_tb
//
//  Simpler than its RX counterpart: result_valid/result_data
//  are already native to `clock`, so this just checks the
//  one-cycle registered pass-through and the fifo_full drop
//  case.
// ============================================================
module TxFIFOWriteCtrl_tb;

parameter CLK_PERIOD = 10;

reg        clock;
reg        reset_n;
reg        result_valid;
reg  [7:0] result_data;
reg        fifo_full;

wire       fifo_wr_en;
wire [7:0] fifo_wr_data;

integer pass_count = 0;
integer fail_count = 0;

TxFIFOWriteCtrl DUT (
    .clock        (clock),
    .reset_n      (reset_n),
    .result_valid (result_valid),
    .result_data  (result_data),
    .fifo_wr_en   (fifo_wr_en),
    .fifo_wr_data (fifo_wr_data),
    .fifo_full    (fifo_full)
);

always #(CLK_PERIOD/2) clock = ~clock;

task check(input cond, input [8*50-1:0] msg);
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

initial begin
    clock = 1'b0;
    reset_n = 1'b0;
    result_valid = 1'b0;
    result_data = 8'd0;
    fifo_full = 1'b0;
    repeat (3) @(posedge clock);
    reset_n = 1'b1;

    // --- Normal push ---
    @(negedge clock);
    result_valid = 1'b1;
    result_data  = 8'h42;
    @(negedge clock);
    result_valid = 1'b0;
    check(fifo_wr_en === 1'b1, "result_valid pulse produces fifo_wr_en on the next edge");
    check(fifo_wr_data === 8'h42, "fifo_wr_data carries result_data correctly");

    @(posedge clock);
    #1;
    check(fifo_wr_en === 1'b0, "fifo_wr_en deasserts after one cycle");

    // --- Drop on full ---
    fifo_full = 1'b1;
    @(negedge clock);
    result_valid = 1'b1;
    result_data  = 8'h99;
    @(negedge clock);
    result_valid = 1'b0;
    check(fifo_wr_en === 1'b0, "result dropped: fifo_wr_en stays low while fifo_full is asserted");
    fifo_full = 1'b0;

    $display("=== TxFIFOWriteCtrl_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT: TxFIFOWriteCtrl_tb did not complete in time");
    $finish;
end

endmodule
