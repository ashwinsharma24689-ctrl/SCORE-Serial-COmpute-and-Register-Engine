
module SIPO(
    input  wire         reset_n,
    input  wire         data_tx,
    input  wire         baud_clk,

    output wire         active_flag,
    output wire         recieved_flag,
    output wire  [10:0] data_parll
);

reg [10:0] temp, data_parll_temp;
reg [3:0]  frame_counter, stop_count;
reg [1:0]  next_state;

localparam IDLE   = 2'b00,
           CENTER = 2'b01,
           FRAME  = 2'b11,
           GET    = 2'b10;

//  Recieving logic FSM
always @(posedge baud_clk, negedge reset_n) begin
  if (!reset_n) begin
    next_state    <= IDLE;
    stop_count    <= 4'd0;
    frame_counter <= 4'd0;
    temp          <= {11{1'b1}};
  end
  else begin
    case (next_state)
      IDLE :
      begin
        temp          <= {11{1'b1}};
        stop_count    <= 4'd0;
        frame_counter <= 4'd0;
        if(~data_tx) begin
          next_state  <= CENTER;
        end
        else begin
          next_state  <= IDLE;
        end
      end

      CENTER :
      begin
        if(stop_count == 4'd6) begin
          stop_count     <= 4'd0;
          next_state     <= GET;
        end
        else begin
          stop_count  <= stop_count + 4'b1;
          next_state  <= CENTER;
        end
      end

      FRAME :
      begin
        temp <= data_parll_temp;
        if(frame_counter == 4'd10) begin
          frame_counter <= 4'd0;
          next_state    <= IDLE;
        end
        else begin
          if(stop_count == 4'd14) begin
            frame_counter  <= frame_counter + 4'b1;
            stop_count     <= 4'd0;
            next_state     <= GET;
          end
          else begin
            frame_counter  <= frame_counter;
            stop_count     <= stop_count + 4'b1;
            next_state     <= FRAME;
          end
        end
      end

      GET : begin
        next_state     <= FRAME;
        temp           <= data_parll_temp;
      end
    endcase
  end
end

always @(*) begin
  case (next_state)
    IDLE, CENTER, FRAME: data_parll_temp  = temp;

    GET : begin
      data_parll_temp    = temp >> 1;
      data_parll_temp[10] = data_tx;
    end
  endcase
end

assign data_parll    = recieved_flag? data_parll_temp : {11{1'b1}};
assign recieved_flag = (frame_counter == 4'd10);
assign active_flag   = !recieved_flag;

endmodule
