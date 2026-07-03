// ============================================================
//  TxFIFOReadCtrl
//
//  Drains the TX SyncFIFO one byte at a time into TxUnit,
//  sequencing `send` against `tx_active_flag`/`tx_done_flag`.
//
//  This is where the TX-side clock-domain crossing actually
//  lives: tx_active_flag and tx_done_flag are produced by
//  PISO's combinational output block, itself paced by FSM
//  state that only changes on baud_clk edges. They are
//  synchronized into the `clock` domain (2-flop each) before
//  this FSM makes decisions on them — mirroring the same
//  technique RxFIFOWriteCtrl used for done_flag on the RX side,
//  just applied to the read side here instead of the write side,
//  since it's the TX path's *handoff to PISO* that crosses
//  domains, not its FIFO push.
// ============================================================
module TxFIFOReadCtrl(
    input  wire        clock,
    input  wire        reset_n,

    //  TX SyncFIFO read port (FWFT)
    input  wire [7:0]   fifo_rd_data,
    input  wire         fifo_empty,
    output reg           fifo_rd_en,

    //  TxUnit interface
    output reg           tx_send,
    output reg  [7:0]    tx_data_in,
    input  wire           tx_active_flag,
    input  wire           tx_done_flag
);

//  2-flop synchronizers on both baud_clk-paced flags.
reg active_s0, active_s1;
reg done_s0,   done_s1;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        active_s0 <= 1'b0;
        active_s1 <= 1'b0;
        done_s0   <= 1'b1;   // PISO idles with done_flag == 1
        done_s1   <= 1'b1;
    end
    else begin
        active_s0 <= tx_active_flag;
        active_s1 <= active_s0;
        done_s0   <= tx_done_flag;
        done_s1   <= done_s0;
    end
end

localparam IDLE         = 2'd0,
           ASSERT_SEND  = 2'd1,
           WAIT_COMPLETE= 2'd2;

reg [1:0] state;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        state       <= IDLE;
        fifo_rd_en  <= 1'b0;
        tx_send     <= 1'b0;
        tx_data_in  <= 8'd0;
    end
    else begin
        fifo_rd_en <= 1'b0;   // default: no pop unless explicitly set below

        case (state)

            //  Wait for a byte, latch it, pop it (FWFT: valid this cycle).
            IDLE: begin
                tx_send <= 1'b0;
                if (!fifo_empty) begin
                    tx_data_in <= fifo_rd_data;
                    fifo_rd_en <= 1'b1;
                    state      <= ASSERT_SEND;
                end
            end

            //  Hold `send` high until PISO has registered it (active_s1
            //  rises), since `send` must be sampled high on a baud_clk
            //  posedge while PISO is idle — a single `clock`-domain
            //  pulse might otherwise be missed if it doesn't overlap
            //  a baud_clk edge.
            ASSERT_SEND: begin
                tx_send <= 1'b1;
                if (active_s1) begin
                    state <= WAIT_COMPLETE;
                end
            end

            //  Drop `send` now that PISO has latched the frame, and
            //  wait for the transmission to fully finish (active_s1
            //  falls, done_s1 rises again) before allowing the next
            //  byte to be popped — PISO cannot accept a new byte
            //  mid-frame.
            WAIT_COMPLETE: begin
                tx_send <= 1'b0;
                if (!active_s1 && done_s1) begin
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
