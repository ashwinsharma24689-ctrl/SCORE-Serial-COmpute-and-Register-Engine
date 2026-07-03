module alu (
    input  [7:0] operand_a,
    input  [7:0] operand_b,
    input  [ 3:0] alu_control,

    output reg [7:0] alu_result,
    output reg        zero_flag,
    output reg        comp_flag,
    output reg        carry_flag,
    output reg        sign_bit,
    output reg        borrow,
    output reg        overflow
);

localparam ADD = 4'b0000,   // funct7[5]=0, funct3=000
           SUB = 4'b1000,   // funct7[5]=1, funct3=000
           AND = 4'b0111,   // funct7[5]=0, funct3=111
           OR  = 4'b0110,   // funct7[5]=0, funct3=110
           XOR = 4'b0100,   // funct7[5]=0, funct3=100
           SLT = 4'b0010,   // funct7[5]=0, funct3=010
           SLTU= 4'b0011,   // funct7[5]=0, funct3=011
           SLL = 4'b0001,   // funct7[5]=0, funct3=001
           SRL = 4'b0101,   // funct7[5]=0, funct3=101
           SRA = 4'b1101;   // funct7[5]=1, funct3=101

//  Shared subtract / add control
wire        is_sub = (alu_control == SUB) || (alu_control == SLT);
wire [7:0]  b_mux  = is_sub ? ~operand_b : operand_b;
wire        cin    = is_sub ? 1'b1       : 1'b0;

//  CLA (Carry-Look-Ahead Adder with BEC)
wire [7:0] sum;
wire       carry_out;

distributed_cla_adder CLA(
    .a    (operand_a),
    .b    (b_mux),
    .c_in (cin),
    .sum  (sum),
    .c_out(carry_out)
);

//  ALU datapath
always @(*) begin
    // Defaults (prevent latches)
    alu_result = 8'd0;
    carry_flag = 1'b0;
    borrow     = 1'b0;
    overflow   = 1'b0;
    comp_flag  = 1'b0;

    case (alu_control)

        ADD: begin
            alu_result = sum;
            carry_flag = carry_out;
            overflow   = (~operand_a[7] & ~operand_b[7] &  sum[7]) |
                         ( operand_a[7] &  operand_b[7] & ~sum[7]);
        end

        SUB: begin
            alu_result = sum;
            carry_flag = carry_out;
            borrow     = ~carry_out;
            overflow   = (~operand_a[7] &  operand_b[7] &  sum[7]) |
                         ( operand_a[7] & ~operand_b[7] & ~sum[7]);
        end

        AND: alu_result = operand_a & operand_b;
        OR : alu_result = operand_a | operand_b;
        XOR: alu_result = operand_a ^ operand_b;

        SLT: begin
            comp_flag  = (operand_a[7] != operand_b[7])
                             ? operand_a[7]
                             : sum[7];
            alu_result = {7'd0, comp_flag};
        end

        SLTU: begin
            comp_flag  = ~carry_out;
            alu_result = {7'd0, comp_flag};
        end

        SLL: alu_result = operand_a << operand_b[2:0];
        SRL: alu_result = operand_a >> operand_b[2:0];
        SRA: alu_result = $signed(operand_a) >>> operand_b[2:0];

        default: alu_result = 8'd0;
    endcase

    zero_flag = (alu_result == 8'd0);
    sign_bit  = alu_result[7];
end

endmodule

module gp_cell (
    input  wire a,
    input  wire b,
    output wire g,
    output wire p
);
    assign g = a & b;
    assign p = a ^ b;
endmodule

module carry_lookahead_network #(
    parameter N = 8
)(
    input  wire [N-1:0] g,
    input  wire [N-1:0] p,
    input  wire         c_in,
    output wire [N:0]   c
);
    assign c[0] = c_in;

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : carry_bit
            wire [i:0] pp;
            assign pp[i] = p[i];

            for (j = i-1; j >= 0; j = j - 1) begin : pp_chain
                assign pp[j] = pp[j+1] & p[j];
            end

            wire [i:0] term;
            for (j = 0; j <= i; j = j + 1) begin : terms
                if (j == 0)
                    assign term[0] = pp[0] & c_in;
                else
                    assign term[j] = pp[j] & g[j-1];
            end

            assign c[i+1] = g[i] | (|term);
        end
    endgenerate
endmodule

module distributed_cla_adder #(
    parameter N = 8
)(
    input  wire [N-1:0] a,
    input  wire [N-1:0] b,
    input  wire         c_in,
    output wire [N-1:0] sum,
    output wire         c_out
);

    wire [N-1:0] g;
    wire [N-1:0] p;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : gp_stage
            gp_cell u_gp (
                .a  (a[i]),
                .b  (b[i]),
                .g  (g[i]),
                .p  (p[i])
            );
        end
    endgenerate

    wire [N:0] c;

    carry_lookahead_network #(.N(N)) u_cln (
        .g    (g),
        .p    (p),
        .c_in (c_in),
        .c    (c)
    );

    generate
        for (i = 0; i < N; i = i + 1) begin : sum_stage
            assign sum[i] = p[i] ^ c[i];
        end
    endgenerate

    assign c_out = c[N];

endmodule
