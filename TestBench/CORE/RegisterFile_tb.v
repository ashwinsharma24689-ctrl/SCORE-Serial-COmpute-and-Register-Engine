`timescale 1ns/1ps
// ============================================================
//  RegisterFile_tb
//
//  Covers: reset clears all 8 registers, x0 hardwired to zero
//  on read regardless of write attempts, write_enable guard,
//  wr==0 guard, and a boundary write/read at address 7.
// ============================================================
module RegisterFile_tb;

parameter CLK_PERIOD = 10;

reg        clk;
reg        rst;
reg        write_enable;
reg  [2:0] sr1, sr2, wr;
reg  [7:0] wd;
wire [7:0] rs1, rs2;

integer pass_count = 0;
integer fail_count = 0;

reg_array DUT (
    .clk          (clk),
    .rst          (rst),
    .write_enable (write_enable),
    .sr1          (sr1),
    .sr2          (sr2),
    .wr           (wr),
    .wd           (wd),
    .rs1          (rs1),
    .rs2          (rs2)
);

always #(CLK_PERIOD/2) clk = ~clk;

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

task write_reg(input [2:0] addr, input [7:0] data);
begin
    @(negedge clk);
    write_enable = 1'b1;
    wr           = addr;
    wd           = data;
    @(negedge clk);
    write_enable = 1'b0;
end
endtask

initial begin
    clk = 1'b0;
    rst = 1'b1;
    write_enable = 1'b0;
    sr1 = 3'd0; sr2 = 3'd0; wr = 3'd0; wd = 8'd0;
    repeat (2) @(posedge clk);
    rst = 1'b0;

    // --- x0 hardwired to zero, even if a write to it is attempted ---
    write_reg(3'd0, 8'hFF);
    sr1 = 3'd0;
    #1; check(rs1 === 8'd0, "x0 reads zero even after attempted write");

    // --- Basic write/read on registers 1..7 ---
    write_reg(3'd1, 8'h11);
    write_reg(3'd2, 8'h22);
    write_reg(3'd7, 8'h77); // boundary address
    sr1 = 3'd1; sr2 = 3'd2;
    #1;
    check(rs1 === 8'h11, "reg1 read back correctly");
    check(rs2 === 8'h22, "reg2 read back correctly");
    sr1 = 3'd7;
    #1; check(rs1 === 8'h77, "boundary address 7 read back correctly");

    // --- write_enable guard: no write should occur when deasserted ---
    @(negedge clk);
    write_enable = 1'b0;
    wr = 3'd1;
    wd = 8'hAA;
    @(negedge clk);
    sr1 = 3'd1;
    #1; check(rs1 === 8'h11, "write_enable=0 correctly blocks the write");

    // --- wr==0 guard: write_enable high but wr==0 must not write x0 ---
    @(negedge clk);
    write_enable = 1'b1;
    wr = 3'd0;
    wd = 8'h55;
    @(negedge clk);
    write_enable = 1'b0;
    sr1 = 3'd0;
    #1; check(rs1 === 8'd0, "wr==0 guard: x0 remains zero despite write_enable");

    // --- Reset clears all registers ---
    @(negedge clk);
    rst = 1'b1;
    @(negedge clk);
    rst = 1'b0;
    sr1 = 3'd1; sr2 = 3'd7;
    #1;
    check(rs1 === 8'd0, "reset clears reg1");
    check(rs2 === 8'd0, "reset clears reg7");

    $display("=== RegisterFile_tb complete: %0d passed, %0d failed ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: %0d TEST(S) FAILED", fail_count);

    $finish;
end

endmodule
