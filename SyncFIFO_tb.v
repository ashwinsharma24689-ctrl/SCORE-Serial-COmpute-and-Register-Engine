`timescale 1ns/1ps
// ============================================================
//  SyncFIFO_tb
//
//  Covers: reset behavior, fill-to-full with overflow rejection,
//  FWFT visibility (data valid before pop), drain-to-empty
//  ordering, and same-cycle read+write.
// ============================================================
module SyncFIFO_tb;

parameter WIDTH      = 8;
parameter DEPTH      = 8;
parameter ADDR_WIDTH = 3;
parameter CLK_PERIOD = 10;

reg                  clk;
reg                  rst_n;
reg                  wr_en;
reg  [WIDTH-1:0]     wr_data;
wire                 full;
reg                  rd_en;
wire [WIDTH-1:0]     rd_data;
wire                 empty;

integer pass_count = 0;
integer fail_count = 0;

SyncFIFO #(.WIDTH(WIDTH), .DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) DUT (
    .clk     (clk),
    .rst_n   (rst_n),
    .wr_en   (wr_en),
    .wr_data (wr_data),
    .full    (full),
    .rd_en   (rd_en),
    .rd_data (rd_data),
    .empty   (empty)
);

always #(CLK_PERIOD/2) clk = ~clk;

task check(input cond, input [8*40-1:0] msg);
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

task fifo_write(input [WIDTH-1:0] data);
begin
    @(negedge clk);
    wr_en   = 1'b1;
    wr_data = data;
    @(negedge clk);
    wr_en   = 1'b0;
end
endtask

// FWFT pop: rd_data must already be valid before this task asserts rd_en.
task fifo_read_and_check(input [WIDTH-1:0] expected);
begin
    check(!empty, "read: fifo not empty when expected data present");
    check(rd_data === expected, "read: rd_data matches expected value before pop");
    @(negedge clk);
    rd_en = 1'b1;
    @(negedge clk);
    rd_en = 1'b0;
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    wr_en = 1'b0;
    rd_en = 1'b0;
    wr_data = 8'd0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    // --- Reset behavior ---
    check(empty === 1'b1, "after reset: empty asserted");
    check(full  === 1'b0, "after reset: full deasserted");

    // --- Fill to full ---
    fifo_write(8'h10);
    fifo_write(8'h20);
    fifo_write(8'h30);
    fifo_write(8'h40);
    fifo_write(8'h50);
    fifo_write(8'h60);
    fifo_write(8'h70);
    fifo_write(8'h80); // 8th write -> DEPTH reached
    check(full === 1'b1, "after 8 writes into DEPTH=8: full asserted");

    // --- Overflow rejection: attempted 9th write while full must be dropped ---
    fifo_write(8'hEE);
    check(full === 1'b1, "still full after rejected 9th write");

    // --- FWFT visibility + drain-to-empty ordering ---
    fifo_read_and_check(8'h10);
    fifo_read_and_check(8'h20);
    fifo_read_and_check(8'h30);
    fifo_read_and_check(8'h40);
    fifo_read_and_check(8'h50);
    fifo_read_and_check(8'h60);
    fifo_read_and_check(8'h70);
    fifo_read_and_check(8'h80); // confirms the rejected 8'hEE never entered the queue
    check(empty === 1'b1, "after draining all 8 entries: empty asserted");

    // --- Same-cycle read + write (steady-state throughput) ---
    fifo_write(8'hA1);
    fifo_write(8'hA2);
    @(negedge clk);
    // pop A1 while pushing A3 in the same cycle
    rd_en   = 1'b1;
    wr_en   = 1'b1;
    wr_data = 8'hA3;
    check(rd_data === 8'hA1, "same-cycle read+write: rd_data is head-of-queue before the pop lands");
    @(negedge clk);
    rd_en = 1'b0;
    wr_en = 1'b0;
    fifo_read_and_check(8'hA2);
    fifo_read_and_check(8'hA3);
    check(empty === 1'b1, "after same-cycle test drains: empty asserted");

    // --- Mid-operation reset ---
    fifo_write(8'h99);
    @(negedge clk);
    rst_n = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    check(empty === 1'b1, "reset mid-operation clears the queue");

    $display("=== SyncFIFO_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

endmodule
