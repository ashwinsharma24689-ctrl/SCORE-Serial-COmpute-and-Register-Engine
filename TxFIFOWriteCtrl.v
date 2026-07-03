// ============================================================
//  TxFIFOWriteCtrl
//
//  Mirror of RxFIFOWriteCtrl's role, but simpler: result_valid /
//  result_data are already native to the `clock` domain (they
//  come straight from CommandExecUnit), so no synchronizer is
//  needed on this side at all — the clock-domain-crossing
//  concern for the TX path lives entirely on the *read* side
//  (TxFIFOReadCtrl), where bytes finally have to be handed off
//  to TxUnit's baud_clk-paced PISO.
// ============================================================
module TxFIFOWriteCtrl(
    input  wire       clock,
    input  wire       reset_n,

    //  From CommandExecUnit
    input  wire       result_valid,
    input  wire [7:0] result_data,

    //  To TX SyncFIFO write port
    output reg         fifo_wr_en,
    output reg  [7:0]   fifo_wr_data,
    input  wire         fifo_full
);

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        fifo_wr_en   <= 1'b0;
        fifo_wr_data <= 8'd0;
    end
    else begin
        fifo_wr_en <= 1'b0;   // default: no write unless conditions below hold

        if (result_valid && !fifo_full) begin
            fifo_wr_en   <= 1'b1;
            fifo_wr_data <= result_data;
        end
        //  If fifo_full happens to coincide with a result_valid pulse,
        //  the byte is dropped rather than corrupting the FIFO. Given
        //  the TX FIFO drains at UART bit-rate speed and results are
        //  produced at most once per 5-byte command (thousands of
        //  `clock` cycles apart), this is a backpressure case worth
        //  being aware of but unlikely to occur with a reasonably
        //  sized FIFO (see SyncFIFO's DEPTH parameter).
    end
end

endmodule
