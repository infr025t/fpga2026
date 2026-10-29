`timescale 1ns/1ps
module row_window5 #(parameter integer W=640,H=480,DATA_W=8)(
 input wire clk,rst,abort,in_valid,input wire [DATA_W-1:0] in_data,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire in_sof,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [5*DATA_W-1:0] out_rows,
 output wire [9:0] out_x,output wire [8:0] out_y,output wire [31:0] out_frame_id);
 localparam integer LATENCY=2;
 initial if(W<5 || W>640 || H<5 || H>480 || DATA_W<1)
   $fatal(1,"illegal row_window5 parameters");
 reg [2:0] bank_index;
 wire [2:0] active_bank=in_sof ? 3'd0 : bank_index;
 wire access_enable=in_valid && !rst && !abort;
 wire [4:0] bank_write_enable=access_enable ? (5'b00001 << active_bank) : 5'b0;
 wire [4:0] bank_read_enable=access_enable ? ~bank_write_enable : 5'b0;
 wire [DATA_W-1:0] bank_data[0:4];
 genvar g;
 generate for(g=0;g<5;g=g+1)begin: bank
   // Each generate scope is one independent single-port synchronous RAM.
   // There is deliberately no reset or clear on memory or read data.
   (* ram_style="block" *) reg [DATA_W-1:0] memory[0:W-1];
   reg [DATA_W-1:0] read_data;
   always @(posedge clk)begin
     if(bank_write_enable[g]) memory[in_x]<=in_data;
     else if(bank_read_enable[g]) read_data<=memory[in_x];
   end
   assign bank_data[g]=read_data;
 end endgenerate
 reg [2:0] role0;
 reg [DATA_W-1:0] current0;
 reg [5*DATA_W-1:0] rows1,rows2;
 reg [2:0] valid_pipe;
 reg [9:0] xp[0:2]; reg [8:0] yp[0:2]; reg [31:0] fp[0:2];
 integer k,source_bank;
 always @(posedge clk)begin
   if(rst || abort)begin bank_index<=0;valid_pipe<=0;end
   else begin
     valid_pipe<={valid_pipe[1:0],in_valid};
     if(in_valid)begin
       if(in_x==W-1) bank_index<=(active_bank==4)?0:active_bank+1'b1;
       else if(in_sof) bank_index<=0;
     end
   end
   role0<=active_bank;current0<=in_data;
   xp[0]<=in_x;yp[0]<=in_y;fp[0]<=in_frame_id;
   for(k=1;k<=2;k=k+1)begin xp[k]<=xp[k-1];yp[k]<=yp[k-1];fp[k]<=fp[k-1];end
   // RAM outputs and the current-row bypass both belong to delayed role0.
   // Mask nonexistent rows so stale/uninitialized RAM cannot leak in warmup.
   for(k=0;k<4;k=k+1)begin
     source_bank=role0+1+k;
     if(source_bank>=5) source_bank=source_bank-5;
     rows1[k*DATA_W+:DATA_W]<=(yp[0]>=4-k)?bank_data[source_bank]:{DATA_W{1'b0}};
   end
   rows1[4*DATA_W+:DATA_W]<=current0;
   rows2<=rows1;
 end
 assign out_valid=valid_pipe[2] && !rst && !abort;
 assign out_rows=rows2;assign out_x=xp[2];assign out_y=yp[2];assign out_frame_id=fp[2];
endmodule
