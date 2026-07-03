// ============================================================
//  RxFIFOWriteCtrl
//
//  Sits between RxUnit and the RX SyncFIFO's write port.
//
//  RxUnit.done_flag is produced by DeFrame, driven off SIPO's
//  FSM which is clocked on baud_clk (a divided/generated clock,
//  mesochronous to `clock` but not the same clock). It cannot
//  be safely used directly as a `clock`-domain write-enable.
//
//  This module:
//    1. Synchronizes done_flag into the `clock` domain (2-flop
//       synchronizer) and edge-detects it to produce a single
//       clean one-cycle pulse per received byte.
//    2. Drops bytes that failed framing/parity checks
//       (error_flag != 0) rather than pushing corrupted data
//       into the command stream.
//    3. Respects fifo_full — never asserts wr_en while full,
//       so a stalled decoder cannot cause memory corruption or
//       silent pointer wraparound inside SyncFIFO.
//
//  This module has no knowledge of packets, opcodes, or the
//  5-byte command format — it only knows "a validated byte
//  arrived." That knowledge lives entirely in RxDecoder.
// ============================================================
module RxFIFOWriteCtrl(
    input  wire        clock,
    input  wire        reset_n,

    //  From RxUnit
    input  wire        rx_done_flag,
    input  wire [7:0]  rx_data_out,
    input  wire [2:0]  rx_error_flag,

    //  To RX SyncFIFO write port
    output reg          fifo_wr_en,
    output reg  [7:0]   fifo_wr_data,
    input  wire         fifo_full
);

//  2-flop synchronizer chain on done_flag, plus one extra stage
//  to allow rising-edge detection on the synchronized signal.
reg sync0, sync1, sync2;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        sync0 <= 1'b0;
        sync1 <= 1'b0;
        sync2 <= 1'b0;
    end
    else begin
        sync0 <= rx_done_flag;
        sync1 <= sync0;
        sync2 <= sync1;
    end
end

//  One-cycle pulse in the `clock` domain per received byte.
wire done_pulse = sync1 & ~sync2;

//  rx_data_out / rx_error_flag are combinational outputs derived
//  from SIPO's held `temp` register, which stays stable across
//  the full baud-clk period surrounding done_flag, so sampling
//  them alongside the synchronized pulse (rather than trying to
//  synchronize them independently) is safe.
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        fifo_wr_en   <= 1'b0;
        fifo_wr_data <= 8'd0;
    end
    else begin
        fifo_wr_en <= 1'b0;   // default: no write unless conditions below hold

        if (done_pulse && !fifo_full && (rx_error_flag == 3'b000)) begin
            fifo_wr_en   <= 1'b1;
            fifo_wr_data <= rx_data_out;
        end
    end
end

endmodule
