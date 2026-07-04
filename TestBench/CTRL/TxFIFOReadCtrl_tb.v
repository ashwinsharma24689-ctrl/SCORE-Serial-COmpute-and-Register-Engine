`timescale 1ns/1ps
// ============================================================
//  TxFIFOReadCtrl_tb
//
//  Drives a behavioral FWFT FIFO stub on the read side, and
//  mimics PISO's tx_active_flag/tx_done_flag with a
//  free-running, deliberately off-grid toggle (as they would
//  arrive from the baud_clk domain in the real design), to
//  verify the send/active/done sequencing.
// ============================================================
module TxFIFOReadCtrl_tb;

parameter CLK_PERIOD = 10;

reg        clock;
reg        reset_n;

reg  [7:0] stub_mem [0:7];
integer    stub_head;
integer    stub_count;
wire       fifo_empty = (stub_count == 0);
wire [7:0] fifo_rd_data = stub_mem[stub_head];
wire       fifo_rd_en;

reg        tx_active_flag;
reg        tx_done_flag;

wire       tx_send;
wire [7:0] tx_data_in;

integer pass_count = 0;
integer fail_count = 0;

TxFIFOReadCtrl DUT (
    .clock        (clock),
    .reset_n      (reset_n),
    .fifo_rd_data (fifo_rd_data),
    .fifo_empty   (fifo_empty),
    .fifo_rd_en   (fifo_rd_en),
    .tx_send      (tx_send),
    .tx_data_in   (tx_data_in),
    .tx_active_flag (tx_active_flag),
    .tx_done_flag   (tx_done_flag)
);

always #(CLK_PERIOD/2) clock = ~clock;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        stub_head  <= 0;
        stub_count <= 0;
    end
    else if (fifo_rd_en && !fifo_empty) begin
        stub_head  <= stub_head + 1;
        stub_count <= stub_count - 1;
    end
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

task push_byte(input [7:0] data);
begin
    stub_mem[stub_head + stub_count] = data;
    stub_count = stub_count + 1;
end
endtask

// Mimics PISO: after tx_send is observed, active_flag rises (off-grid delay),
// stays high for a "transmission", then falls and done_flag reasserts.
task mimic_piso_transmission;
begin
    @(posedge tx_send);
    #7; // off-grid relative to clock, mimicking baud_clk-domain latency
    tx_active_flag = 1'b1;
    tx_done_flag   = 1'b0;
    #53; // "transmission" duration, also off-grid
    tx_active_flag = 1'b0;
    #7;
    tx_done_flag   = 1'b1;
end
endtask

initial begin
    clock = 1'b0;
    reset_n = 1'b0;
    stub_head = 0;
    stub_count = 0;
    tx_active_flag = 1'b0;
    tx_done_flag   = 1'b1; // PISO idles with done_flag == 1
    repeat (3) @(posedge clock);
    reset_n = 1'b1;

    push_byte(8'hDE);
    push_byte(8'hAD);

    fork
        mimic_piso_transmission;
        begin
            @(posedge tx_send);
            #1;
            check(tx_data_in === 8'hDE, "first byte: tx_data_in latched correctly before send");
        end
    join

    check(tx_send === 1'b0, "first byte: tx_send dropped after PISO completed the frame");

    fork
        mimic_piso_transmission;
        begin
            @(posedge tx_send);
            #1;
            check(tx_data_in === 8'hAD, "second byte: tx_data_in latched correctly, popped after first fully completed");
        end
    join

    check(stub_count === 0, "both bytes drained from the FIFO stub");

    $display("=== TxFIFOReadCtrl_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT: TxFIFOReadCtrl_tb did not complete in time");
    $finish;
end

endmodule
