`timescale 1ns/1ps
// Passive diagnostic sample: x=1,3,... and y=0,2,...; never controls video flow.
module video_snapshot #(parameter integer W=640,H=480,BLOCK_WORDS=128)(
  input wire clk,rst,start,pixel_valid,input wire[7:0]pixel,input wire[9:0]x,input wire[8:0]y,
  input wire source_done,crop_edge,input wire[7:0]raw_pixel,input wire[10:0]read_command,
  output reg[BLOCK_WORDS*16-1:0]block_data,output wire[31:0]status
);
  localparam integer WORDS=W*H/4;
  (* ram_style="block" *)reg[15:0]memory[0:WORDS-1];
  reg[16:0]samples=0,base=0;reg[7:0]other=0,sequence_id=0;
  reg active_crop=0;
  wire[16:0]target_words=active_crop?(W-10)*(H-10)/4:WORDS;
  reg capture_busy=0,capture_done=0,reading=0,read_pending=0,ack=0;
  reg[2:0]error=0;reg[10:0]seen_command=0;reg[7:0]issue=0,retire=0;
  reg[15:0]read_word;
  wire sample_selected=pixel_valid && x[0] && !y[0];
  wire write_en=capture_busy && sample_selected && samples<target_words;
  wire read_en=reading && issue<BLOCK_WORDS;
  wire[16:0]read_address=base+issue;
  assign status={error,sequence_id,ack,reading,capture_busy,capture_done,samples};
  // Neither memory port is reset. Reset applies only to ownership/valid state.
  always @(posedge clk)begin
    if(write_en)memory[samples]<={raw_pixel,pixel};
    if(read_en)begin if(read_address<target_words)read_word<=memory[read_address];else read_word<=0;end
  end
  always @(posedge clk)begin
    if(rst)begin
      samples<=0;base<=0;other<=0;sequence_id<=0;capture_busy<=0;capture_done<=0;
      reading<=0;read_pending<=0;ack<=0;error<=0;seen_command<=0;issue<=0;retire<=0;block_data<=0;
    end else begin
      read_pending<=read_en;

      if(write_en)samples<=samples+1'b1;
      if(capture_busy && sample_selected && samples>=target_words)error<=3;
      if(capture_busy && source_done)begin
        capture_busy<=0;
        if(samples+(write_en?1:0)==target_words)capture_done<=1;else error<=1;
      end
      if(read_en)issue<=issue+1'b1;
      if(read_pending)begin
        block_data<={read_word,block_data[BLOCK_WORDS*16-1:16]};
        if(retire==BLOCK_WORDS-1)begin reading<=0;ack<=seen_command[10];end
        else retire<=retire+1'b1;
      end
      if(!reading && read_command!=seen_command)begin
        seen_command<=read_command;
        if(!capture_done || capture_busy || read_command[9:0]*BLOCK_WORDS>=target_words)error<=2;
        else begin
          base<=read_command[9:0]*BLOCK_WORDS;issue<=0;retire<=0;reading<=1;block_data<=0;
        end
      end
      if(start)begin
        active_crop<=crop_edge;samples<=0;other<=0;sequence_id<=sequence_id+1'b1;capture_busy<=1;capture_done<=0;
        if(reading)error<=4;else error<=0;
        reading<=0;read_pending<=0;
      end
    end
  end
  initial if(W%2 || H%2 || BLOCK_WORDS<2 || BLOCK_WORDS>128)
    $fatal(1,"invalid diagnostic snapshot dimensions");
endmodule
