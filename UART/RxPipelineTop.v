// ============================================================
//  RxPipelineTop
//
//  Integrates the physical/framing layer (RxUnit) with the
//  protocol layer (RxDecoder) through an 8-bit-wide FWFT FIFO.
//
//  Layering, made concrete by this module's structure:
//
//    RxUnit            -- baud_clk-paced, byte-at-a-time,
//                          protocol-agnostic UART receiver
//         |
//    RxFIFOWriteCtrl   -- clock-domain crossing + error filtering
//         |
//    SyncFIFO (8-bit)  -- rate decoupling only, no protocol
//         |                knowledge, single clock domain (clock)
//    RxDecoder         -- clock-domain, 5-byte packet assembly,
//                          zero knowledge of RxUnit or baud_clk
//         |
//    cmd_valid + decoded fields --> ALU / register file control
// ============================================================
module RxPipelineTop #(
    parameter FIFO_DEPTH      = 8,
    parameter FIFO_ADDR_WIDTH = 3     // = $clog2(FIFO_DEPTH)
)(
    input  wire         reset_n,
    input  wire         clock,          // system clock (decoder / FIFO domain)
    input  wire         data_tx,        // serial line in from the host
    input  wire [1:0]   parity_type,
    input  wire [1:0]   baud_rate,

    //  Decoded command interface, ready for the ALU/register-file
    //  control logic to consume
    output wire         cmd_valid,
    output wire         imm_sel,
    output wire [3:0]   alu_control,
    output wire [2:0]   sr1,
    output wire [2:0]   sr2,
    output wire [2:0]   wr,
    output wire [7:0]   immediate,

    //  Exposed for visibility/debug — not required by the decoder
    output wire         rx_active_flag,
    output wire [2:0]   rx_error_flag
);

//  Interconnect
wire        rx_done_flag_w;
wire [7:0]  rx_data_out_w;

wire        fifo_wr_en_w;
wire [7:0]  fifo_wr_data_w;
wire        fifo_full_w;

wire        fifo_rd_en_w;
wire [7:0]  fifo_rd_data_w;
wire        fifo_empty_w;

//  Physical/framing layer — unmodified, baud_clk-paced.
RxUnit RxUnitInst(
    .reset_n     (reset_n),
    .data_tx     (data_tx),
    .clock       (clock),
    .parity_type (parity_type),
    .baud_rate   (baud_rate),

    .active_flag (rx_active_flag),
    .done_flag   (rx_done_flag_w),
    .error_flag  (rx_error_flag),
    .data_out    (rx_data_out_w)
);

//  Clock-domain crossing + error filtering into the clock domain.
RxFIFOWriteCtrl WriteCtrlInst(
    .clock         (clock),
    .reset_n       (reset_n),

    .rx_done_flag  (rx_done_flag_w),
    .rx_data_out   (rx_data_out_w),
    .rx_error_flag (rx_error_flag),

    .fifo_wr_en    (fifo_wr_en_w),
    .fifo_wr_data  (fifo_wr_data_w),
    .fifo_full     (fifo_full_w)
);

//  Rate-decoupling FIFO — 8 bits wide, FWFT read behavior.
SyncFIFO #(
    .WIDTH      (8),
    .DEPTH      (FIFO_DEPTH),
    .ADDR_WIDTH (FIFO_ADDR_WIDTH)
) RxFIFOInst (
    .clk     (clock),
    .rst_n   (reset_n),

    .wr_en   (fifo_wr_en_w),
    .wr_data (fifo_wr_data_w),
    .full    (fifo_full_w),

    .rd_en   (fifo_rd_en_w),
    .rd_data (fifo_rd_data_w),
    .empty   (fifo_empty_w)
);

//  Protocol layer — assembles the fixed 5-byte command packet.
RxDecoder RxDecoderInst(
    .clock       (clock),
    .reset_n     (reset_n),

    .fifo_rd_data(fifo_rd_data_w),
    .fifo_empty  (fifo_empty_w),
    .fifo_rd_en  (fifo_rd_en_w),

    .cmd_valid   (cmd_valid),
    .imm_sel     (imm_sel),
    .alu_control (alu_control),
    .sr1         (sr1),
    .sr2         (sr2),
    .wr          (wr),
    .immediate   (immediate)
);

endmodule
