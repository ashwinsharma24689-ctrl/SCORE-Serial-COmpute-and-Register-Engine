`timescale 1ns/1ps
// ============================================================
//  CommandExecUnit_tb
//
//  Instantiates CommandExecUnit against the real reg_array and
//  alu modules (its actual neighbors), driving cmd_valid and
//  the decoded fields directly -- exactly as RxDecoder would --
//  without needing RxDecoder or any FIFO in the loop.
// ============================================================
module CommandExecUnit_tb;

parameter CLK_PERIOD = 10;

reg        clock;
reg        reset_n;

reg        cmd_valid;
reg        imm_sel;
reg  [3:0] alu_control;
reg  [2:0] sr1, sr2, wr;
reg  [7:0] immediate;

wire [2:0] regfile_sr1, regfile_sr2, regfile_wr;
wire       regfile_write_enable;
wire [7:0] regfile_wd;
wire [7:0] regfile_rs1, regfile_rs2;

wire [7:0] alu_operand_a, alu_operand_b;
wire [3:0] alu_alu_control;
wire [7:0] alu_result;

wire       result_valid;
wire [7:0] result_data;

integer pass_count = 0;
integer fail_count = 0;

localparam ADD = 4'h0, SUB = 4'h8;

CommandExecUnit DUT (
    .clock       (clock),
    .reset_n     (reset_n),
    .cmd_valid   (cmd_valid),
    .imm_sel     (imm_sel),
    .alu_control (alu_control),
    .sr1         (sr1),
    .sr2         (sr2),
    .wr          (wr),
    .immediate   (immediate),

    .regfile_sr1          (regfile_sr1),
    .regfile_sr2          (regfile_sr2),
    .regfile_wr           (regfile_wr),
    .regfile_write_enable (regfile_write_enable),
    .regfile_wd           (regfile_wd),
    .regfile_rs1          (regfile_rs1),
    .regfile_rs2          (regfile_rs2),

    .alu_operand_a  (alu_operand_a),
    .alu_operand_b  (alu_operand_b),
    .alu_alu_control(alu_alu_control),
    .alu_result     (alu_result),

    .result_valid (result_valid),
    .result_data  (result_data)
);

reg_array REGFILE (
    .clk          (clock),
    .rst          (~reset_n),
    .write_enable (regfile_write_enable),
    .sr1          (regfile_sr1),
    .sr2          (regfile_sr2),
    .wr           (regfile_wr),
    .wd           (regfile_wd),
    .rs1          (regfile_rs1),
    .rs2          (regfile_rs2)
);

alu ALU (
    .operand_a   (alu_operand_a),
    .operand_b   (alu_operand_b),
    .alu_control (alu_alu_control),
    .alu_result  (alu_result),
    .zero_flag   (), .comp_flag(), .carry_flag(), .sign_bit(), .borrow(), .overflow()
);

always #(CLK_PERIOD/2) clock = ~clock;

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

task issue_cmd(input imm_sel_in, input [3:0] alu_ctrl_in, input [2:0] sr1_in,
               input [2:0] sr2_in, input [2:0] wr_in, input [7:0] imm_in);
begin
    @(negedge clock);
    imm_sel     = imm_sel_in;
    alu_control = alu_ctrl_in;
    sr1         = sr1_in;
    sr2         = sr2_in;
    wr          = wr_in;
    immediate   = imm_in;
    cmd_valid   = 1'b1;
    @(negedge clock);
    cmd_valid   = 1'b0;
end
endtask

initial begin
    clock = 1'b0;
    reset_n = 1'b0;
    cmd_valid = 1'b0;
    imm_sel = 1'b0; alu_control = 4'd0; sr1 = 3'd0; sr2 = 3'd0; wr = 3'd0; immediate = 8'd0;
    repeat (3) @(posedge clock);
    reset_n = 1'b1;

    // --- Load-immediate trick: sr1=0 (x0), imm_sel=1, ADD -> reg1 = immediate ---
    issue_cmd(1'b1, ADD, 3'd0, 3'd0, 3'd1, 8'h10);
    if (!result_valid) @(posedge result_valid);
    #1;
    check(result_data === 8'h10, "load-immediate: result_data reflects immediate via x0+imm");
    #1; // allow reg_array's synchronous write to complete on this same edge
    @(negedge clock);
    check(REGFILE.register_array[1] === 8'h10, "load-immediate: reg1 written back correctly");

    // --- Second load-immediate: reg2 = 0x05 ---
    issue_cmd(1'b1, ADD, 3'd0, 3'd0, 3'd2, 8'h05);
    if (!result_valid) @(posedge result_valid);
    @(negedge clock);
    check(REGFILE.register_array[2] === 8'h05, "load-immediate: reg2 written back correctly");

    // --- Register-register ADD: reg3 = reg1 + reg2 = 0x15 ---
    issue_cmd(1'b0, ADD, 3'd1, 3'd2, 3'd3, 8'h00);
    if (!result_valid) @(posedge result_valid);
    #1;
    check(result_data === 8'h15, "reg-reg ADD: result_data = reg1+reg2");
    @(negedge clock);
    check(REGFILE.register_array[3] === 8'h15, "reg-reg ADD: reg3 written back correctly");

    // --- Compute-without-store: wr=0, SUB reg1-reg2, verify no register mutated ---
    issue_cmd(1'b0, SUB, 3'd1, 3'd2, 3'd0, 8'h00);
    if (!result_valid) @(posedge result_valid);
    #1;
    check(result_data === (8'h10 - 8'h05), "compute-without-store: result_data correct");
    @(negedge clock);
    check(REGFILE.register_array[1] === 8'h10, "compute-without-store: reg1 unchanged");
    check(REGFILE.register_array[2] === 8'h05, "compute-without-store: reg2 unchanged");

    // --- result_valid must be a single-cycle pulse ---
    @(posedge clock);
    #1;
    check(result_valid === 1'b0, "result_valid deasserts after one cycle");

    $display("=== CommandExecUnit_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT: CommandExecUnit_tb did not complete in time");
    $finish;
end

endmodule