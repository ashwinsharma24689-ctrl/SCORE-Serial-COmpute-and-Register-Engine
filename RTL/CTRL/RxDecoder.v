// ============================================================
//  RxDecoder
//
//  Consumes bytes from the FWFT RX SyncFIFO's read port and
//  assembles them into one decoded 5-byte command:
//
//    Byte 0 : opcode   = { imm_sel, 3'b reserved, alu_control[3:0] }
//    Byte 1 : sr1      = { 5'b reserved, sr1[2:0] }
//    Byte 2 : sr2      = { 5'b reserved, sr2[2:0] }
//    Byte 3 : wr       = { 5'b reserved, wr[2:0]  }
//    Byte 4 : immediate = full 8-bit value
//
//  Has no knowledge of RxUnit, baud_clk, or UART framing at
//  all — its entire world is the FIFO's read port (rd_data /
//  empty / rd_en). This keeps it testable by driving the FIFO's
//  write port directly in a testbench, with zero UART timing
//  simulation required.
//
//  cmd_valid pulses for exactly one `clock` cycle once all 5
//  bytes have been captured, handing the ALU / register-file
//  control logic a single atomic "command ready" event instead
//  of five separate byte-arrival events.
// ============================================================
module RxDecoder(
    input  wire       clock,
    input  wire       reset_n,

    //  RX SyncFIFO read port (FWFT)
    input  wire [7:0]  fifo_rd_data,
    input  wire        fifo_empty,
    output wire        fifo_rd_en,

    //  Decoded command, valid for one cycle alongside cmd_valid
    //  (and held stable afterward until the next command completes)
    output reg          cmd_valid,
    output reg          imm_sel,
    output reg [3:0]    alu_control,
    output reg [2:0]    sr1,
    output reg [2:0]    sr2,
    output reg [2:0]    wr,
    output reg [7:0]    immediate
);

//  FSM state encoding
localparam IDLE     = 3'd0,
           OPCODE   = 3'd1,
           SR1_ST   = 3'd2,
           SR2_ST   = 3'd3,
           WR_ST    = 3'd4,
           IMM_ST   = 3'd5,
           DISPATCH = 3'd6;

reg [2:0] state;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        state       <= IDLE;
        cmd_valid   <= 1'b0;
        imm_sel     <= 1'b0;
        alu_control <= 4'd0;
        sr1         <= 3'd0;
        sr2         <= 3'd0;
        wr          <= 3'd0;
        immediate   <= 8'd0;
    end
    else begin
        //  Defaults each cycle — overridden explicitly below where needed.
        //  Keeping this as a default (rather than only setting it on
        //  transitions) prevents accidental latch inference and keeps
        //  cmd_valid a clean one-cycle pulse. fifo_rd_en is driven
        //  combinationally below (see assign), not registered here.
        cmd_valid  <= 1'b0;

        case (state)

            //  IDLE doubles as the OPCODE-wait state: nothing has been
            //  latched yet, so waiting for byte 0 and capturing it are
            //  the same step.
            IDLE: begin
                if (!fifo_empty) begin
                    imm_sel     <= fifo_rd_data[7];
                    alu_control <= fifo_rd_data[3:0];
                    state       <= SR1_ST;
                end
            end

            SR1_ST: begin
                if (!fifo_empty) begin
                    sr1        <= fifo_rd_data[2:0];
                    state      <= SR2_ST;
                end
            end

            SR2_ST: begin
                if (!fifo_empty) begin
                    sr2        <= fifo_rd_data[2:0];
                    state      <= WR_ST;
                end
            end

            WR_ST: begin
                if (!fifo_empty) begin
                    wr         <= fifo_rd_data[2:0];
                    state      <= IMM_ST;
                end
            end

            IMM_ST: begin
                if (!fifo_empty) begin
                    immediate  <= fifo_rd_data;   // full byte, no slicing
                    state      <= DISPATCH;
                end
            end

            //  Dedicated dispatch state: keeps cmd_valid decoupled from
            //  fifo_empty entirely, so downstream ALU/regfile control
            //  logic never has to reason about FIFO state, only cmd_valid.
            DISPATCH: begin
                cmd_valid <= 1'b1;
                state     <= IDLE;
            end

            default: state <= IDLE;

        endcase
    end
end

//  fifo_rd_en must be combinational, not registered: the FIFO's own read
//  pointer is a flip-flop that samples fifo_rd_en on the same clock edge
//  this FSM's state register updates on. If fifo_rd_en were registered
//  here too, it would need one extra edge to reach the FIFO, so every
//  captured byte would be one cycle (and one FIFO word) stale. Driving
//  it straight off the current state keeps FSM state transitions and
//  FIFO pops on the exact same edge, matching real FWFT timing.
assign fifo_rd_en = !fifo_empty && (state == IDLE   || state == SR1_ST ||
                                     state == SR2_ST || state == WR_ST  ||
                                     state == IMM_ST);

endmodule