module PISO(
    input wire           reset_n,            
    input wire           send,               
    input wire           baud_clk,           
    input wire           parity_bit,         
    input wire [7:0]     data_in,            
  
    output reg 	         data_tx, 	         
	output reg 	         active_flag,        
	output reg  	     done_flag 	         
);

//  Internal declarations
reg [3:0]   stop_count;
reg [10:0]  frame_r;
reg [10:0]  frame_man;
reg         next_state;
wire        count_full;

//  Encoding the states
localparam IDLE   = 1'b0,
           ACTIVE = 1'b1;

//  Frame generation
always @(posedge baud_clk, negedge reset_n) begin
    if (!reset_n)        frame_r <= {11{1'b1}};
    else if (next_state) frame_r <= frame_r;
    else                 frame_r <= {1'b1,parity_bit,data_in,1'b0};
end

// Counter logic
always @(posedge baud_clk, negedge reset_n) begin
    if (!reset_n || !next_state || count_full) stop_count <= 4'd0;
    else  stop_count <= stop_count + 4'd1;
end
assign count_full     = (stop_count == 4'd11);

//  Transmission logic FSM
always @(posedge baud_clk, negedge reset_n) begin
    if (!reset_n) next_state   <= IDLE;
	else
	begin
		if (!next_state) begin
            if (send) next_state   <= ACTIVE;
            else      next_state   <= IDLE;
        end
        else begin
            if (count_full) next_state   <= IDLE;
            else            next_state   <= ACTIVE;
        end
	end 
end

always @(*) begin
    if (reset_n && next_state && (stop_count != 4'd0)) begin
        data_tx      = frame_man[0];
        frame_man    = frame_man >> 1;
        active_flag  = 1'b1;
        done_flag    = 1'b0;
    end
    else begin
        data_tx      = 1'b1;
        frame_man    = frame_r;
        active_flag  = 1'b0;
        done_flag    = 1'b1;
    end
end

endmodule  