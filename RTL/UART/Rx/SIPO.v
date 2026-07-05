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
reg        frame_done;   //  Sticky "byte ready" flag.
reg [10:0] hold_data;    //  Latched copy of the completed frame.

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
    frame_done    <= 1'b0;
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
          frame_done  <= 1'b0;   //  Clear once a new byte starts arriving.
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
          frame_done    <= 1'b1;   //  Latch "byte ready" until next start bit.
          hold_data     <= data_parll_temp;  //  Snapshot the finished frame.
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

assign data_parll    = frame_done ? hold_data : {11{1'b1}};
assign recieved_flag = frame_done;
assign active_flag   = (next_state != IDLE);

endmodule
