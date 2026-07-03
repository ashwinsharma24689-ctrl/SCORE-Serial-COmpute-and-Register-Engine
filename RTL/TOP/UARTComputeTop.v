
module UARTComputeTop #(
    parameter FIFO_DEPTH      = 8,
    parameter FIFO_ADDR_WIDTH = 3     // = $clog2(FIFO_DEPTH)
)(
    input  wire        reset_n,
    input  wire        clock,          // system clock

    //  Serial lines to/from the host — two independent wires,
    //  not a loopback (unlike the original UARTTOPMOD).
    input  wire        rx_serial_in,
    output wire         tx_serial_out,

    input  wire  [1:0]  parity_type,
    input  wire  [1:0]  baud_rate,

    //  Debug/visibility outputs
    output wire          rx_active_flag,
    output wire  [2:0]   rx_error_flag,
    output wire           tx_active_flag,
    output wire           tx_done_flag
);

//  ----------------------------------------------------------
//  RX side interconnect
//  ----------------------------------------------------------
wire        rx_done_flag_w;
wire [7:0]  rx_data_out_w;

wire        rxfifo_wr_en_w;
wire [7:0]  rxfifo_wr_data_w;
wire        rxfifo_full_w;

wire        rxfifo_rd_en_w;
wire [7:0]  rxfifo_rd_data_w;
wire        rxfifo_empty_w;

wire        cmd_valid_w;
wire        imm_sel_w;
wire [3:0]  alu_control_w;
wire [2:0]  sr1_w, sr2_w, wr_w;
wire [7:0]  immediate_w;

//  ----------------------------------------------------------
//  Compute-core interconnect
//  ----------------------------------------------------------
wire [2:0]  regfile_sr1_w, regfile_sr2_w, regfile_wr_w;
wire        regfile_write_enable_w;
wire [7:0]  regfile_wd_w;
wire [7:0]  regfile_rs1_w, regfile_rs2_w;

wire [7:0]  alu_operand_a_w, alu_operand_b_w;
wire [3:0]  alu_alu_control_w;
wire [7:0]  alu_result_w;

wire        result_valid_w;
wire [7:0]  result_data_w;

//  ----------------------------------------------------------
//  TX side interconnect
//  ----------------------------------------------------------
wire        txfifo_wr_en_w;
wire [7:0]  txfifo_wr_data_w;
wire        txfifo_full_w;

wire        txfifo_rd_en_w;
wire [7:0]  txfifo_rd_data_w;
wire        txfifo_empty_w;

wire        tx_send_w;
wire [7:0]  tx_data_in_w;

//  ============================================================
//  RX PATH
//  ============================================================

RxUnit RxUnitInst(
    .reset_n     (reset_n),
    .data_tx     (rx_serial_in),
    .clock       (clock),
    .parity_type (parity_type),
    .baud_rate   (baud_rate),

    .active_flag (rx_active_flag),
    .done_flag   (rx_done_flag_w),
    .error_flag  (rx_error_flag),
    .data_out    (rx_data_out_w)
);

RxFIFOWriteCtrl RxWriteCtrlInst(
    .clock         (clock),
    .reset_n       (reset_n),

    .rx_done_flag  (rx_done_flag_w),
    .rx_data_out   (rx_data_out_w),
    .rx_error_flag (rx_error_flag),

    .fifo_wr_en    (rxfifo_wr_en_w),
    .fifo_wr_data  (rxfifo_wr_data_w),
    .fifo_full     (rxfifo_full_w)
);

SyncFIFO #(
    .WIDTH      (8),
    .DEPTH      (FIFO_DEPTH),
    .ADDR_WIDTH (FIFO_ADDR_WIDTH)
) RxFIFOInst (
    .clk     (clock),
    .rst_n   (reset_n),

    .wr_en   (rxfifo_wr_en_w),
    .wr_data (rxfifo_wr_data_w),
    .full    (rxfifo_full_w),

    .rd_en   (rxfifo_rd_en_w),
    .rd_data (rxfifo_rd_data_w),
    .empty   (rxfifo_empty_w)
);

RxDecoder RxDecoderInst(
    .clock       (clock),
    .reset_n     (reset_n),

    .fifo_rd_data(rxfifo_rd_data_w),
    .fifo_empty  (rxfifo_empty_w),
    .fifo_rd_en  (rxfifo_rd_en_w),

    .cmd_valid   (cmd_valid_w),
    .imm_sel     (imm_sel_w),
    .alu_control (alu_control_w),
    .sr1         (sr1_w),
    .sr2         (sr2_w),
    .wr          (wr_w),
    .immediate   (immediate_w)
);

//  ============================================================
//  COMPUTE CORE
//  ============================================================

CommandExecUnit CommandExecInst(
    .clock       (clock),
    .reset_n     (reset_n),

    .cmd_valid   (cmd_valid_w),
    .imm_sel     (imm_sel_w),
    .alu_control (alu_control_w),
    .sr1         (sr1_w),
    .sr2         (sr2_w),
    .wr          (wr_w),
    .immediate   (immediate_w),

    .regfile_sr1          (regfile_sr1_w),
    .regfile_sr2          (regfile_sr2_w),
    .regfile_wr           (regfile_wr_w),
    .regfile_write_enable (regfile_write_enable_w),
    .regfile_wd           (regfile_wd_w),
    .regfile_rs1          (regfile_rs1_w),
    .regfile_rs2          (regfile_rs2_w),

    .alu_operand_a  (alu_operand_a_w),
    .alu_operand_b  (alu_operand_b_w),
    .alu_alu_control(alu_alu_control_w),
    .alu_result     (alu_result_w),

    .result_valid (result_valid_w),
    .result_data  (result_data_w)
);

reg_array RegisterFileInst(
    .clk          (clock),
    .rst          (~reset_n),
    .write_enable (regfile_write_enable_w),
    .sr1          (regfile_sr1_w),
    .sr2          (regfile_sr2_w),
    .wr           (regfile_wr_w),
    .wd           (regfile_wd_w),
    .rs1          (regfile_rs1_w),
    .rs2          (regfile_rs2_w)
);

alu ALUInst(
    .operand_a   (alu_operand_a_w),
    .operand_b   (alu_operand_b_w),
    .alu_control (alu_alu_control_w),
    .alu_result  (alu_result_w),
    .zero_flag   (),
    .comp_flag   (),
    .carry_flag  (),
    .sign_bit    (),
    .borrow      (),
    .overflow    ()
);

//  ============================================================
//  TX PATH
//  ============================================================

TxFIFOWriteCtrl TxWriteCtrlInst(
    .clock        (clock),
    .reset_n      (reset_n),

    .result_valid (result_valid_w),
    .result_data  (result_data_w),

    .fifo_wr_en   (txfifo_wr_en_w),
    .fifo_wr_data (txfifo_wr_data_w),
    .fifo_full    (txfifo_full_w)
);

SyncFIFO #(
    .WIDTH      (8),
    .DEPTH      (FIFO_DEPTH),
    .ADDR_WIDTH (FIFO_ADDR_WIDTH)
) TxFIFOInst (
    .clk     (clock),
    .rst_n   (reset_n),

    .wr_en   (txfifo_wr_en_w),
    .wr_data (txfifo_wr_data_w),
    .full    (txfifo_full_w),

    .rd_en   (txfifo_rd_en_w),
    .rd_data (txfifo_rd_data_w),
    .empty   (txfifo_empty_w)
);

TxFIFOReadCtrl TxReadCtrlInst(
    .clock       (clock),
    .reset_n     (reset_n),

    .fifo_rd_data(txfifo_rd_data_w),
    .fifo_empty  (txfifo_empty_w),
    .fifo_rd_en  (txfifo_rd_en_w),

    .tx_send        (tx_send_w),
    .tx_data_in     (tx_data_in_w),
    .tx_active_flag (tx_active_flag),
    .tx_done_flag   (tx_done_flag)
);

TxUnit TxUnitInst(
    .reset_n     (reset_n),
    .send        (tx_send_w),
    .clock       (clock),
    .parity_type (parity_type),
    .baud_rate   (baud_rate),
    .data_in     (tx_data_in_w),

    .data_tx     (tx_serial_out),
    .active_flag (tx_active_flag),
    .done_flag   (tx_done_flag)
);

endmodule
