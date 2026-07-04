`timescale 1ns/1ps
// ============================================================
//  UARTTOPMOD_tb
//
//  Single shared testbench for the entire UART physical layer,
//  exercised through the internal TX->RX loopback in
//  UARTTOPMOD. Covers TxUnit, RxUnit, PISO, SIPO, Parity,
//  ErrorCheck, DeFrame, BaudGenT, BaudGenR without any
//  per-submodule testbenches.
//
//  REQUIRES the corrected BaudGeneratorR_fixed.v (module
//  renamed to BaudGenR) and SIPO_fixed.v (reset/case ordering
//  fix) in place of the originals, or RxUnit will not elaborate
//  or will not reset cleanly.
//
//  Strategy: drive TxUnit.send/data_in, let the internal
//  loopback carry the serial waveform straight into RxUnit,
//  and self-check data_out == data_in with error_flag == 0
//  once rx_done_flag pulses. Repeated across both parity modes
//  and two baud rates.
// ============================================================
module UARTTOPMOD_tb;

parameter CLK_PERIOD = 20; // 50 MHz

reg         reset_n;
reg         send;
reg         clock;
reg  [1:0]  parity_type;
reg  [1:0]  baud_rate;
reg  [7:0]  data_in;

wire        tx_active_flag;
wire        tx_done_flag;
wire        rx_active_flag;
wire        rx_done_flag;
wire [7:0]  data_out;
wire [2:0]  error_flag;

integer pass_count = 0;
integer fail_count = 0;

UARTTOPMOD DUT (
    .reset_n     (reset_n),
    .send        (send),
    .clock       (clock),
    .parity_type (parity_type),
    .baud_rate   (baud_rate),
    .data_in     (data_in),

    .tx_active_flag (tx_active_flag),
    .tx_done_flag   (tx_done_flag),
    .rx_active_flag (rx_active_flag),
    .rx_done_flag   (rx_done_flag),
    .data_out       (data_out),
    .error_flag     (error_flag)
);

always #(CLK_PERIOD/2) clock = ~clock;

// Safety net: never let the sim hang forever on a stuck DUT.
initial begin
    #20_000_000;
    $display("TIMEOUT: simulation did not complete in time -- check reset/CDC behavior");
    $finish;
end

task send_byte(input [7:0] data);
begin
    @(negedge clock);
    data_in = data;
    send    = 1'b1;
    @(negedge clock);
    send    = 1'b0;

    // Wait for PISO to actually start, then finish, the frame.
    wait (tx_active_flag == 1'b1);
    wait (tx_active_flag == 1'b0);

    // Wait for SIPO/DeFrame to declare the frame fully received.
    @(posedge rx_done_flag);
    #1; // let combinational data_out/error_flag settle

    if (data_out !== data) begin
        $display("FAIL  sent=%02h  got=%02h  error_flag=%03b", data, data_out, error_flag);
        fail_count = fail_count + 1;
    end
    else if (error_flag !== 3'b000) begin
        $display("FAIL  sent=%02h  got=%02h  error_flag=%03b (framing/parity error)", data, data_out, error_flag);
        fail_count = fail_count + 1;
    end
    else begin
        $display("PASS  sent=%02h  got=%02h  error_flag=%03b", data, data_out, error_flag);
        pass_count = pass_count + 1;
    end

    // Let the line settle fully before the next byte.
    repeat (20) @(posedge clock);
end
endtask

// TX-side bit period in system-clock cycles, derived from BaudGenT's
// final_value table (baud_clk toggles every final_value ticks, so one
// full bit period = 2 * final_value).
function integer tx_bit_period;
    input [1:0] br;
    integer fv;
begin
    case (br)
        2'b00: fv = 10417; // BAUD24
        2'b01: fv = 5208;  // BAUD48
        2'b10: fv = 2604;  // BAUD96
        2'b11: fv = 1302;  // BAUD192
        default: fv = 2604;
    endcase
    tx_bit_period = 2 * fv;
end
endfunction

// --- Addition 1: baud_clk period measurement ---
// Confirms BaudGenT's divider produces the actual expected period in ns,
// not just internal TX/RX self-consistency (which the loopback tests above
// would still pass even if both dividers were wrong by the same factor).
task check_baud_rate(input [1:0] br, input [8*10-1:0] label);
    real t0, t1, measured_period, expected_period;
begin
    reset_n     = 1'b0;
    baud_rate   = br;
    parity_type = 2'b01;
    send        = 1'b0;
    repeat (5) @(posedge clock);
    reset_n = 1'b1;

    expected_period = 1.0 * tx_bit_period(br) * CLK_PERIOD;

    @(posedge DUT.Transmitter.baud_clk_w);
    t0 = $realtime;
    @(posedge DUT.Transmitter.baud_clk_w);
    t1 = $realtime;
    measured_period = t1 - t0;

    if (measured_period == expected_period) begin
        pass_count = pass_count + 1;
        $display("PASS  baud_clk period (%0s): measured=%0.1fns expected=%0.1fns", label, measured_period, expected_period);
    end
    else begin
        fail_count = fail_count + 1;
        $display("FAIL  baud_clk period (%0s): measured=%0.1fns expected=%0.1fns", label, measured_period, expected_period);
    end
end
endtask

// --- Addition 2: fault injection ---
// Loopback alone can only ever carry a correctly-generated frame, since
// nothing corrupts the line -- ErrorCheck's actual detection path is
// otherwise never exercised. This forces the internal loopback wire
// (TxUnit.data_tx -> RxUnit.data_tx) to flip mid-parity-bit, and confirms
// ErrorCheck's parity_flag (error_flag[0]) correctly catches it.
task inject_fault_and_check(input [7:0] data, input [1:0] br, input [1:0] pt);
    integer bit_period, wait_cycles;
begin
    reset_n     = 1'b0;
    baud_rate   = br;
    parity_type = pt;
    send        = 1'b0;
    data_in     = 8'd0;
    repeat (5) @(posedge clock);
    reset_n = 1'b1;
    repeat (5) @(posedge clock);

    bit_period = tx_bit_period(br);

    @(negedge clock);
    data_in = data;
    send    = 1'b1;
    @(negedge clock);
    send    = 1'b0;

    wait (tx_active_flag == 1'b1);

    // Bit order on the wire: start(0), data[0..7], parity(9), stop(10).
    // Land mid-way through the parity bit (index 9).
    wait_cycles = 9 * bit_period + bit_period / 2;
    repeat (wait_cycles) @(posedge clock);

    force DUT.data_tx_w = ~DUT.data_tx_w;
    repeat (50) @(posedge clock);
    release DUT.data_tx_w;

    wait (tx_active_flag == 1'b0);
    @(posedge rx_done_flag);
    #1;

    if (error_flag[0] === 1'b1) begin
        pass_count = pass_count + 1;
        $display("PASS  fault-injection: corrupted parity bit correctly flagged, error_flag=%03b", error_flag);
    end
    else begin
        fail_count = fail_count + 1;
        $display("FAIL  fault-injection: corrupted parity bit NOT flagged, error_flag=%03b", error_flag);
    end

    repeat (20) @(posedge clock);
end
endtask

task run_config(input [1:0] br, input [1:0] pt, input [8*8-1:0] label);
    integer i;
    reg [7:0] vectors [0:5];
begin
    $display("--- config: %0s  baud_rate=%0d  parity_type=%0d ---", label, br, pt);

    reset_n     = 1'b0;
    baud_rate   = br;
    parity_type = pt;
    send        = 1'b0;
    data_in     = 8'd0;
    repeat (5) @(posedge clock);
    reset_n = 1'b1;
    repeat (5) @(posedge clock);

    vectors[0] = 8'h00;
    vectors[1] = 8'hFF;
    vectors[2] = 8'hA5;
    vectors[3] = 8'h5A;
    vectors[4] = 8'h01;
    vectors[5] = 8'h80;

    for (i = 0; i < 6; i = i + 1)
        send_byte(vectors[i]);
end
endtask

initial begin
    clock = 1'b0;

    // BAUD192 (fastest, keeps sim time reasonable) at both parity modes.
    run_config(2'b11, 2'b01, "BAUD192/ODD ");
    run_config(2'b11, 2'b10, "BAUD192/EVEN");

    // One slower baud rate to confirm the divider ratio itself is correct,
    // not just that BAUD192 happens to work.
    run_config(2'b10, 2'b01, "BAUD96/ODD  ");

    // --- Absolute baud-rate correctness (not just TX/RX self-consistency) ---
    $display("--- baud_clk period measurement ---");
    check_baud_rate(2'b11, "BAUD192");
    check_baud_rate(2'b10, "BAUD96");

    // --- Fault injection: confirms ErrorCheck's detection path actually works ---
    $display("--- fault injection ---");
    inject_fault_and_check(8'hA5, 2'b11, 2'b01);
    inject_fault_and_check(8'h3C, 2'b10, 2'b10);

    $display("=== UARTTOPMOD_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

endmodule
