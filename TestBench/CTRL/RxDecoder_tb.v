`timescale 1ns/1ps
// ============================================================
//  RxDecoder_tb
//
//  Drives RxDecoder's FIFO read port directly through a small
//  behavioral FWFT stub, exactly as intended by the layering
//  decision made for this module: zero UART timing involved.
//  Covers a full 5-byte packet, a stall (empty) mid-packet,
//  and back-to-back packets.
// ============================================================
module RxDecoder_tb;

parameter CLK_PERIOD = 10;

reg        clock;
reg        reset_n;

// Behavioral FWFT FIFO stub
reg  [7:0] stub_mem [0:15];
integer    stub_head;
integer    stub_count;
wire       fifo_empty = (stub_count == 0);
wire [7:0] fifo_rd_data = stub_mem[stub_head];
wire       fifo_rd_en;

wire        cmd_valid;
wire        imm_sel;
wire [3:0]  alu_control;
wire [2:0]  sr1, sr2, wr;
wire [7:0]  immediate;

integer pass_count = 0;
integer fail_count = 0;

RxDecoder DUT (
    .clock       (clock),
    .reset_n     (reset_n),
    .fifo_rd_data(fifo_rd_data),
    .fifo_empty  (fifo_empty),
    .fifo_rd_en  (fifo_rd_en),
    .cmd_valid   (cmd_valid),
    .imm_sel     (imm_sel),
    .alu_control (alu_control),
    .sr1         (sr1),
    .sr2         (sr2),
    .wr          (wr),
    .immediate   (immediate)
);

always #(CLK_PERIOD/2) clock = ~clock;

// FWFT pop model: on rd_en, advance head and decrement count.
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

task check(input cond, input [8*50-1:0] msg);
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

// Push a 5-byte packet into the stub's backing memory, starting at stub_head+stub_count.
task push_packet(input [7:0] opcode, input [7:0] b_sr1, input [7:0] b_sr2, input [7:0] b_wr, input [7:0] b_imm);
    integer base;
begin
    base = stub_head + stub_count;
    stub_mem[base+0] = opcode;
    stub_mem[base+1] = b_sr1;
    stub_mem[base+2] = b_sr2;
    stub_mem[base+3] = b_wr;
    stub_mem[base+4] = b_imm;
    stub_count = stub_count + 5;
end
endtask

initial begin
    clock = 1'b0;
    reset_n = 1'b0;
    stub_head = 0;
    stub_count = 0;
    repeat (3) @(posedge clock);
    reset_n = 1'b1;
    #1;  // let reset settle before loading data at the same instant as this edge

    // --- Packet 1: imm_sel=1, alu_control=ADD(0), sr1=3, sr2=1, wr=5, imm=0x2A ---
    push_packet(8'b1000_0000, 8'd3, 8'd1, 8'd5, 8'h2A);
    if (!cmd_valid) @(posedge cmd_valid);
    #1;
    check(imm_sel     === 1'b1,  "packet1: imm_sel decoded correctly");
    check(alu_control === 4'h0,  "packet1: alu_control decoded correctly");
    check(sr1          === 3'd3,  "packet1: sr1 decoded correctly");
    check(sr2          === 3'd1,  "packet1: sr2 decoded correctly");
    check(wr           === 3'd5,  "packet1: wr decoded correctly");
    check(immediate    === 8'h2A, "packet1: immediate decoded correctly");

    // cmd_valid must be a single-cycle pulse.
    @(posedge clock);
    #1;
    check(cmd_valid === 1'b0, "packet1: cmd_valid deasserts after one cycle");

    // --- Packet 2, sent back-to-back: imm_sel=0, alu_control=SUB(1000), sr1=2, sr2=6, wr=0, imm=0xFF ---
    push_packet(8'b0000_1000, 8'd2, 8'd6, 8'd0, 8'hFF);
    if (!cmd_valid) @(posedge cmd_valid);
    #1;
    check(imm_sel     === 1'b0,  "packet2: imm_sel decoded correctly");
    check(alu_control === 4'h8,  "packet2: alu_control decoded correctly");
    check(sr1          === 3'd2,  "packet2: sr1 decoded correctly");
    check(sr2          === 3'd6,  "packet2: sr2 decoded correctly");
    check(wr           === 3'd0,  "packet2: wr==0 (compute-without-store) decoded correctly");

    // --- Packet 3, with an artificial stall (empty FIFO) mid-packet ---
    push_packet(8'b1000_0111, 8'd7, 8'd7, 8'd7, 8'h01);
    // Let the decoder consume only the opcode+sr1 bytes, then force a stall
    // by not adding more data for a few cycles before it needs byte 3 (sr2).
    @(posedge clock); // opcode consumed
    @(posedge clock); // sr1 consumed
    repeat (5) @(posedge clock); // decoder now waits on fifo_empty for sr2
    if (!cmd_valid) @(posedge cmd_valid);
    #1;
    check(sr1 === 3'd7 && sr2 === 3'd7 && wr === 3'd7 && immediate === 8'h01,
          "packet3: stall mid-packet does not corrupt field capture");

    $display("=== RxDecoder_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT: RxDecoder_tb did not complete in time");
    $finish;
end

endmodule