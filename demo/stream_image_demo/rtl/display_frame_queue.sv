`timescale 1ns/1ps
// Two complete-frame slots. A slow/missing display drops NEW whole frames;
// acquisition and processing never wait for out_ready. Uncommitted frames
// remain invisible. frame_start precedes the first input pixel by >=1 clock.
module display_frame_queue #(parameter integer W=316,H=236)(
  input wire clk,rst,frame_start,frame_abort,
  input wire[31:0]in_frame_id,input wire in_processed,
  input wire in_valid,input wire[7:0]in_pixel,input wire in_last,
  output reg dropped,malformed,output wire[1:0]level,
  output reg out_valid,input wire out_ready,output wire[7:0]out_pixel,
  output reg[31:0]out_frame_id,output reg out_processed,
  output wire out_sof,out_eol,out_eof,output reg frame_delivered
);
  localparam integer PIXELS=W*H,AW=(PIXELS<2)?1:$clog2(PIXELS+1);
  (* ram_style="block" *) reg[7:0]memory0[0:PIXELS-1],memory1[0:PIXELS-1];
  reg[7:0]q0,q1;
  reg[1:0]occupied,ready_frames;
  reg write_ptr,read_ptr,writing,reading,read_bank;
  reg[AW-1:0]write_index,next_read,out_index;
  reg[31:0]ids[0:1];reg processed[0:1];
  wire delivered=out_valid && out_ready && out_eof;
  wire can_admit=!occupied[write_ptr] || (delivered && read_bank==write_ptr);
  wire start_read=!reading && ready_frames[read_ptr];
  wire advance_read=reading && (!out_valid || out_ready) && next_read<PIXELS;
  wire load=start_read || advance_read;
  wire[AW-1:0]address=start_read?0:next_read;
  assign out_pixel=read_bank?q1:q0;
  assign out_sof=out_valid && out_index==0;
  assign out_eol=out_valid && (out_index%W)==W-1;
  assign out_eof=out_valid && out_index==PIXELS-1;
  assign level={1'b0,occupied[0]}+{1'b0,occupied[1]};
  always @(posedge clk)begin
    if(in_valid && writing && !frame_abort && !frame_start && !rst)begin
      if(!write_ptr)memory0[write_index]<=in_pixel;
      else memory1[write_index]<=in_pixel;
    end
    if(load && !rst)begin q0<=memory0[address];q1<=memory1[address];end
  end
  always @(posedge clk)begin
    if(rst)begin
      occupied<=0;ready_frames<=0;write_ptr<=0;read_ptr<=0;writing<=0;reading<=0;read_bank<=0;
      write_index<=0;next_read<=0;out_index<=0;out_valid<=0;out_frame_id<=0;out_processed<=0;
      dropped<=0;malformed<=0;frame_delivered<=0;ids[0]<=0;ids[1]<=0;processed[0]<=0;processed[1]<=0;
    end else begin
      dropped<=0;malformed<=0;frame_delivered<=delivered;
      if(delivered)begin
        occupied[read_bank]<=0;reading<=0;out_valid<=0;read_ptr<=!read_ptr;
      end
      if(start_read)begin
        read_bank<=read_ptr;reading<=1;ready_frames[read_ptr]<=0;
        out_frame_id<=ids[read_ptr];out_processed<=processed[read_ptr];
        out_valid<=1;out_index<=0;next_read<=1;
      end else if(advance_read)begin
        out_valid<=1;out_index<=next_read;next_read<=next_read+1'b1;
      end
      if(frame_abort && writing)begin occupied[write_ptr]<=0;writing<=0;end
      if(frame_start)begin
        if(writing)begin
          // Reject an overlapping producer frame; caller must restart cleanly.
          occupied[write_ptr]<=0;writing<=0;malformed<=1;
        end else if(can_admit)begin
          occupied[write_ptr]<=1;writing<=1;write_index<=0;
          ids[write_ptr]<=in_frame_id;processed[write_ptr]<=in_processed;
        end else begin writing<=0;dropped<=1;end
      end else if(in_valid && writing && !frame_abort)begin
        if(in_last || write_index==PIXELS-1)begin
          writing<=0;
          if(in_last && write_index==PIXELS-1)begin
            ready_frames[write_ptr]<=1;write_ptr<=!write_ptr;
          end else begin occupied[write_ptr]<=0;malformed<=1;end
        end else write_index<=write_index+1'b1;
      end
    end
  end
endmodule
