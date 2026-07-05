// ============================================================
//  SyncFIFO — Generic parameterized synchronous FIFO
//
//  First-Word-Fall-Through (FWFT) read behavior:
//    - rd_data reflects the current head-of-queue entry
//      COMBINATIONALLY, valid any cycle empty == 0.
//    - rd_en simply advances the read pointer (pops) the
//      currently-visible word; no extra latency cycle needed
//      to "see" the data before popping it.
//
//  Single clock domain only (RX decoder and RX FIFO both live
//  on `clock`, not `baud_clk` — the baud_clk-to-clock crossing
//  is handled separately, upstream of this module's write port,
//  by RxFIFOWriteCtrl).
// ============================================================
module SyncFIFO #(
    parameter WIDTH      = 8,
    parameter DEPTH      = 8,                 // must be a power of 2
    parameter ADDR_WIDTH = 3                  // = $clog2(DEPTH)
)(
    input  wire             clk,
    input  wire             rst_n,

    //  Write port
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire              full,

    //  Read port (FWFT)
    input  wire              rd_en,
    output wire [WIDTH-1:0]  rd_data,
    output wire              empty
);

//  Storage
reg [WIDTH-1:0] mem [0:DEPTH-1];

//  Pointers carry one extra MSB beyond the address width so that
//  full vs empty can be distinguished without a separate counter:
//  equal pointers (including the extra bit) => empty;
//  equal address bits but differing extra bit => full.
reg [ADDR_WIDTH:0] wr_ptr;
reg [ADDR_WIDTH:0] rd_ptr;

wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

assign empty = (wr_ptr == rd_ptr);
assign full  = (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
               (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

//  FWFT: head entry is always combinationally visible.
assign rd_data = mem[rd_addr];

//  Write logic — synchronous, guarded against writing while full.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
    end
    else if (wr_en && !full) begin
        mem[wr_addr] <= wr_data;
        wr_ptr       <= wr_ptr + 1'b1;
    end
end

//  Read logic — synchronous, guarded against popping while empty.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
    end
    else if (rd_en && !empty) begin
        rd_ptr <= rd_ptr + 1'b1;
    end
end

endmodule
