`timescale 1ns/1ps
// ============================================================
//  UARTComputeTop_tb
//
//  System-level test: acts as the "host," bit-banging real
//  5-byte command packets onto rx_serial_in at the configured
//  baud rate/parity, and decoding the serial response on
//  tx_serial_out -- exercising every module in the pipeline
//  (RxUnit -> RxFIFOWriteCtrl -> SyncFIFO -> RxDecoder ->
//  CommandExecUnit -> reg_array/alu -> TxFIFOWriteCtrl ->
//  SyncFIFO -> TxFIFOReadCtrl -> TxUnit) through their real,
//  fully-wired interfaces rather than any stub.
//
//  REQUIRES the corrected BaudGeneratorR_fixed.v / SIPO_fixed.v
//  in place of the originals.
// ============================================================
module UARTComputeTop_tb;

parameter CLK_PERIOD = 20; // 50 MHz

// Fixed test configuration: BAUD192 (fastest divider, keeps sim
// time reasonable) and ODD parity.
localparam TB_BAUD_RATE   = 2'b11;
localparam TB_PARITY_TYPE = 2'b01;

// One UART bit period = 16 oversample ticks * baud_clk period.
// For BAUD192, BaudGenR's final_value = 81 system-clock ticks
// per baud_clk toggle (half period), so:
//   bit period = 16 * (2 * 81) = 2592 system clock cycles
localparam BIT_CYCLES = 2592;

localparam ADD = 4'h0, SUB = 4'h8, SLT = 4'h2;

reg  reset_n;
reg  clock;
reg  rx_serial_in;
wire tx_serial_out;
reg  [1:0] parity_type;
reg  [1:0] baud_rate;

wire rx_active_flag;
wire [2:0] rx_error_flag;
wire tx_active_flag;
wire tx_done_flag;

integer pass_count = 0;
integer fail_count = 0;

UARTComputeTop DUT (
    .reset_n     (reset_n),
    .clock       (clock),
    .rx_serial_in(rx_serial_in),
    .tx_serial_out(tx_serial_out),
    .parity_type (parity_type),
    .baud_rate   (baud_rate),
    .rx_active_flag(rx_active_flag),
    .rx_error_flag (rx_error_flag),
    .tx_active_flag(tx_active_flag),
    .tx_done_flag  (tx_done_flag)
);

always #(CLK_PERIOD/2) clock = ~clock;

initial begin
    #50_000_000;
    $display("TIMEOUT: UARTComputeTop_tb did not complete in time");
    $finish;
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

// Drives one UART byte onto rx_serial_in: start, 8 data bits
// LSB-first, parity, stop -- mirroring PISO's own bit order
// exactly, since that's what a real host would produce.
task host_send_byte(input [7:0] data);
    integer i;
    reg parity_bit;
begin
    case (TB_PARITY_TYPE)
        2'b01: parity_bit = (^data) ? 1'b0 : 1'b1; // ODD
        2'b10: parity_bit = (^data) ? 1'b1 : 1'b0; // EVEN
        default: parity_bit = 1'b1;
    endcase

    rx_serial_in = 1'b0;                 // start bit
    repeat (BIT_CYCLES) @(posedge clock);
    for (i = 0; i < 8; i = i + 1) begin
        rx_serial_in = data[i];
        repeat (BIT_CYCLES) @(posedge clock);
    end
    rx_serial_in = parity_bit;
    repeat (BIT_CYCLES) @(posedge clock);
    rx_serial_in = 1'b1;                 // stop bit
    repeat (BIT_CYCLES) @(posedge clock);
end
endtask

// Sends a full 5-byte command packet.
task send_command(input imm_sel, input [3:0] alu_ctrl, input [2:0] sr1,
                   input [2:0] sr2, input [2:0] wr, input [7:0] imm);
    reg [7:0] opcode;
begin
    opcode = {imm_sel, 3'b000, alu_ctrl};
    host_send_byte(opcode);
    host_send_byte({5'b0, sr1});
    host_send_byte({5'b0, sr2});
    host_send_byte({5'b0, wr});
    host_send_byte(imm);
end
endtask

// Samples tx_serial_out (idle-high) for the single response byte.
task host_receive_byte(output [7:0] data);
    integer i;
    reg [7:0] rxd;
begin
    @(negedge tx_serial_out);            // start bit begins
    repeat (BIT_CYCLES + BIT_CYCLES/2) @(posedge clock); // skip start, land mid data bit0
    for (i = 0; i < 8; i = i + 1) begin
        rxd[i] = tx_serial_out;
        repeat (BIT_CYCLES) @(posedge clock);
    end
    data = rxd;
    // remaining parity + stop bits are skipped intentionally --
    // ErrorCheck/DeFrame on the loopback UART testbench already
    // covers framing/parity correctness in depth.
end
endtask

reg [7:0] response;

initial begin
    clock = 1'b0;
    reset_n = 1'b0;
    rx_serial_in = 1'b1; // idle high
    parity_type = TB_PARITY_TYPE;
    baud_rate   = TB_BAUD_RATE;
    repeat (5) @(posedge clock);
    reset_n = 1'b1;
    repeat (5) @(posedge clock);

    // --- Command 1: load-immediate, reg1 = 0x0A ---
    send_command(1'b1, ADD, 3'd0, 3'd0, 3'd1, 8'h0A);
    host_receive_byte(response);
    check(response === 8'h0A, "cmd1 load-immediate reg1=0x0A: response byte correct");
    check(DUT.RegisterFileInst.register_array[1] === 8'h0A, "cmd1: reg1 written back correctly");

    // --- Command 2: load-immediate, reg2 = 0x05 ---
    send_command(1'b1, ADD, 3'd0, 3'd0, 3'd2, 8'h05);
    host_receive_byte(response);
    check(response === 8'h05, "cmd2 load-immediate reg2=0x05: response byte correct");
    check(DUT.RegisterFileInst.register_array[2] === 8'h05, "cmd2: reg2 written back correctly");

    // --- Command 3: reg3 = reg1 + reg2 = 0x0F ---
    send_command(1'b0, ADD, 3'd1, 3'd2, 3'd3, 8'h00);
    host_receive_byte(response);
    check(response === 8'h0F, "cmd3 reg1+reg2: response byte correct");
    check(DUT.RegisterFileInst.register_array[3] === 8'h0F, "cmd3: reg3 written back correctly");

    // --- Command 4: compute-without-store, reg1 - reg2, wr=0 ---
    send_command(1'b0, SUB, 3'd1, 3'd2, 3'd0, 8'h00);
    host_receive_byte(response);
    check(response === 8'h05, "cmd4 reg1-reg2 (wr=0): response byte correct");
    check(DUT.RegisterFileInst.register_array[3] === 8'h0F, "cmd4: reg3 unaffected by a wr=0 command");

    // --- Command 5: SLT signed comparison, reg2 < reg1 -> 1, wr=4 ---
    send_command(1'b0, SLT, 3'd2, 3'd1, 3'd4, 8'h00);
    host_receive_byte(response);
    check(response === 8'h01, "cmd5 SLT reg2<reg1: response byte correct");

    $display("=== UARTComputeTop_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

endmodule
