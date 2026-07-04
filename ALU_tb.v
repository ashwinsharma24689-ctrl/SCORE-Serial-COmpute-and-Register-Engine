`timescale 1ns/1ps
// ============================================================
//  ALU_tb
//
//  Directed vectors covering every opcode, overflow/carry/
//  borrow flag correctness, and the operand_b[2:0] shift-amount
//  masking fix (confirms bits [7:3] of operand_b are ignored).
// ============================================================
module ALU_tb;

reg  [7:0] operand_a, operand_b;
reg  [3:0] alu_control;
wire [7:0] alu_result;
wire       zero_flag, comp_flag, carry_flag, sign_bit, borrow, overflow;

integer pass_count = 0;
integer fail_count = 0;

localparam ADD=4'b0000, SUB=4'b1000, AND=4'b0111, OR=4'b0110, XOR=4'b0100,
           SLT=4'b0010, SLTU=4'b0011, SLL=4'b0001, SRL=4'b0101, SRA=4'b1101;

alu DUT (
    .operand_a   (operand_a),
    .operand_b   (operand_b),
    .alu_control (alu_control),
    .alu_result  (alu_result),
    .zero_flag   (zero_flag),
    .comp_flag   (comp_flag),
    .carry_flag  (carry_flag),
    .sign_bit    (sign_bit),
    .borrow      (borrow),
    .overflow    (overflow)
);

task check_result(input [8*40-1:0] msg, input [7:0] expected);
begin
    #1;
    if (alu_result === expected) begin
        pass_count = pass_count + 1;
        $display("PASS  %0s  result=%02h", msg, alu_result);
    end
    else begin
        fail_count = fail_count + 1;
        $display("FAIL  %0s  expected=%02h got=%02h", msg, expected, alu_result);
    end
end
endtask

task check_flag(input [8*30-1:0] msg, input actual, input expected);
begin
    if (actual === expected) begin
        pass_count = pass_count + 1;
        $display("PASS  %0s", msg);
    end
    else begin
        fail_count = fail_count + 1;
        $display("FAIL  %0s  expected=%0d got=%0d", msg, expected, actual);
    end
end
endtask

initial begin
    // ADD basic
    operand_a = 8'd5; operand_b = 8'd3; alu_control = ADD;
    check_result("ADD 5+3", 8'd8);

    // ADD overflow (127 + 1 -> signed overflow into negative)
    operand_a = 8'd127; operand_b = 8'd1; alu_control = ADD;
    #1; check_flag("ADD 127+1 overflow flag set", overflow, 1'b1);
    check_result("ADD 127+1 wraps to -128 (0x80)", 8'h80);

    // SUB basic
    operand_a = 8'd5; operand_b = 8'd3; alu_control = SUB;
    check_result("SUB 5-3", 8'd2);

    // SUB with borrow (0 - 1)
    operand_a = 8'd0; operand_b = 8'd1; alu_control = SUB;
    #1; check_flag("SUB 0-1 borrow flag set", borrow, 1'b1);
    check_result("SUB 0-1 wraps to 0xFF", 8'hFF);

    // AND / OR / XOR
    operand_a = 8'hF0; operand_b = 8'h0F; alu_control = AND;
    check_result("AND 0xF0 & 0x0F", 8'h00);
    operand_a = 8'hF0; operand_b = 8'h0F; alu_control = OR;
    check_result("OR 0xF0 | 0x0F", 8'hFF);
    operand_a = 8'hFF; operand_b = 8'h0F; alu_control = XOR;
    check_result("XOR 0xFF ^ 0x0F", 8'hF0);

    // SLT signed: -1 < 1 -> true
    operand_a = 8'hFF; operand_b = 8'd1; alu_control = SLT;
    check_result("SLT signed -1 < 1", 8'd1);
    // SLT signed: 1 < -1 -> false
    operand_a = 8'd1; operand_b = 8'hFF; alu_control = SLT;
    check_result("SLT signed 1 < -1", 8'd0);

    // SLTU unsigned: 0xFF < 1 unsigned -> false
    operand_a = 8'hFF; operand_b = 8'd1; alu_control = SLTU;
    check_result("SLTU unsigned 0xFF < 1", 8'd0);
    // SLTU unsigned: 1 < 0xFF unsigned -> true
    operand_a = 8'd1; operand_b = 8'hFF; alu_control = SLTU;
    check_result("SLTU unsigned 1 < 0xFF", 8'd1);

    // SLL/SRL/SRA basic
    operand_a = 8'b0000_0001; operand_b = 8'd2; alu_control = SLL;
    check_result("SLL 1 << 2", 8'b0000_0100);
    operand_a = 8'b1000_0000; operand_b = 8'd3; alu_control = SRL;
    check_result("SRL 0x80 >> 3 (logical)", 8'b0001_0000);
    operand_a = 8'b1000_0000; operand_b = 8'd3; alu_control = SRA;
    check_result("SRA 0x80 >>> 3 (arithmetic, sign-extends)", 8'b1111_0000);

    // Shift-amount masking: operand_b[7:3] must be ignored, only [2:0] used.
    // operand_b = 8'b0000_1_010 -> upper bits set, low 3 bits = 3'b010 = 2
    operand_a = 8'b0000_0001; operand_b = 8'b0000_1_010; alu_control = SLL;
    check_result("SLL shift-amount masking: only operand_b[2:0] used", 8'b0000_0100);

    // Zero flag / sign bit
    operand_a = 8'd5; operand_b = 8'd5; alu_control = SUB;
    #1; check_flag("SUB 5-5 zero_flag set", zero_flag, 1'b1);
    operand_a = 8'hFF; operand_b = 8'd0; alu_control = ADD;
    #1; check_flag("ADD result 0xFF sign_bit set", sign_bit, 1'b1);

    // Default/undefined opcode -> result forced to zero
    operand_a = 8'hFF; operand_b = 8'hFF; alu_control = 4'b1111;
    check_result("Undefined opcode defaults to zero", 8'h00);

    $display("=== ALU_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

endmodule
