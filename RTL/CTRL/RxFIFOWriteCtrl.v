
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
