`timescale 1ns/1ps
// Selected pixels feed UART and the public display tap from the same node.
module edge_uart_stream #(parameter W=640,H=480,IDLE_TIMEOUT=200000000)(
 input wire clk,rst,start,filter_id,view_edge,input wire[31:0]frame_id,
 input wire[10:0]epsilon,edge_threshold,
 input wire source_valid,input wire[7:0]source_pixel,input wire[9:0]source_x,
 input wire[8:0]source_y,input wire source_done,source_error,
 output wire source_ready,uart_txd,output reg busy,done,output reg[7:0]error,
 output wire display_valid,output wire[7:0]display_pixel,display_raw,display_edge,
 output wire[9:0]display_x,output wire[8:0]display_y,output wire[31:0]display_frame_id,
 output wire display_sof,display_eol,display_eof);
 localparam N=(W-10)*(H-10),IDLE=0,HEADER=1,BODY=2,DRAIN=3,FOOTER=4,FINISH=5;
 reg[2:0]state;reg active_filter,active_view;reg[10:0]active_eps,active_threshold;
 reg[31:0]active_frame,hcrc,pcrc,scrc,inputs,outputs,idle_count;
 reg[5:0]hi,fi;reg[6:0]cooldown;reg end_seen;
 reg[9:0]ix,ox;reg[8:0]iy,oy;
 wire cv,cs,cl,ce,core_error;wire[7:0]cp,cr,cg;wire[9:0]cx;wire[8:0]cy;wire[31:0]cf;
 wire tx_ready;reg tx_valid;reg[7:0]tx_byte;
 wire coords_ok=source_x==ix&&source_y==iy;
 wire core_abort=!busy||source_error||error!=0;
 assign source_ready=(state==BODY||state==DRAIN)&&inputs<W*H&&cooldown==0&&!source_error&&error==0&&!rst;
 wire accept=source_valid&&source_ready;
 edge_core #(W,H) core(.clk(clk),.rst(rst),.abort(core_abort),.in_valid(accept&&coords_ok),
 .in_pixel(source_pixel),.in_x(source_x),.in_y(source_y),.in_sof(inputs==0),.in_frame_id(active_frame),
 .filter_id(active_filter),.view_edge(active_view),.epsilon(active_eps),.edge_threshold(active_threshold),
 .out_valid(cv),.out_pixel(cp),.out_raw(cr),.out_edge(cg),.out_x(cx),.out_y(cy),.out_frame_id(cf),
 .out_sof(cs),.out_eol(cl),.out_eof(ce),.error(core_error));
 assign display_valid=cv&&!core_error&&!source_error&&error==0;
 assign {display_pixel,display_raw,display_edge,display_x,display_y,display_frame_id,display_sof,display_eol,display_eof}={cp,cr,cg,cx,cy,cf,cs,cl,ce};
 uart_fast_tx uart(.clk(clk),.rst(rst||source_error||error!=0),.valid(tx_valid&&!source_error&&!core_error),.data(tx_byte),.ready(tx_ready),.tx(uart_txd));
 function automatic[31:0]crc_byte(input[31:0]crc,input[7:0]value);
 reg[31:0]c;integer k;begin c=crc^value;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end endfunction
 function automatic[7:0]header_byte(input[5:0]n);
 reg[31:0]v;begin v=0;case(n)
 0:header_byte="E";1:header_byte="V";2:header_byte="G";3:header_byte="2";
 4:header_byte=2;5:header_byte={7'd0,active_view};6:header_byte={7'd0,active_filter};7:header_byte=32;
 8,9:begin v=W-10;header_byte=v>>(8*(n-8));end
 10,11:begin v=H-10;header_byte=v>>(8*(n-10));end
 12,13,14,15:header_byte=active_frame>>(8*(n-12));
 16,17,18,19:header_byte=N>>(8*(n-16));
 20,21:header_byte=active_eps>>(8*(n-20));22,23:header_byte=active_threshold>>(8*(n-22));
 24:header_byte=5;25,26,27:header_byte=0;
 28,29,30,31:header_byte=(~hcrc)>>(8*(n-28));default:header_byte=0;
 endcase end endfunction
 function automatic[7:0]footer_byte(input[5:0]n);
 begin case(n)
 0,1,2,3:footer_byte=(~pcrc)>>(8*n);
 4,5,6,7:footer_byte=(~scrc)>>(8*(n-4));
 8,9,10,11:footer_byte=inputs>>(8*(n-8));
 12,13,14,15:footer_byte=outputs>>(8*(n-12));
 default:footer_byte=0;
 endcase end endfunction
 always @*begin
  tx_valid=0;tx_byte=0;
  case(state)
   HEADER:begin tx_valid=1;tx_byte=header_byte(hi);end
   BODY:if(cv)begin tx_valid=1;tx_byte=cp;end
   FOOTER:begin tx_valid=1;tx_byte=footer_byte(fi);end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  done<=0;
  if(rst)begin
   state<=IDLE;busy<=0;done<=0;error<=0;active_filter<=0;active_view<=0;
   active_eps<=1024;active_threshold<=96;active_frame<=0;hcrc<=32'hffffffff;
   pcrc<=32'hffffffff;scrc<=32'hffffffff;inputs<=0;outputs<=0;idle_count<=0;
   hi<=0;fi<=0;cooldown<=0;end_seen<=0;ix<=0;iy<=0;ox<=5;oy<=5;
  end else begin
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(!busy)begin
    if(start)begin
     state<=HEADER;busy<=1;error<=0;active_filter<=filter_id;active_view<=view_edge;
     active_eps<=epsilon;active_threshold<=edge_threshold;active_frame<=frame_id;
     hcrc<=32'hffffffff;pcrc<=32'hffffffff;scrc<=32'hffffffff;inputs<=0;outputs<=0;
     hi<=0;fi<=0;cooldown<=0;end_seen<=0;ix<=0;iy<=0;ox<=5;oy<=5;idle_count<=0;
    end
   end else if(source_error||core_error||(accept&&!coords_ok)||
    (source_done&&(end_seen||inputs+accept!=W*H))||
    (cv&&(state!=BODY||!tx_ready||cx!=ox||cy!=oy||cf!=active_frame||outputs>=N||
     cs!=(outputs==0)||cl!=(ox==W-6)||ce!=(outputs==N-1)))||idle_count==IDLE_TIMEOUT-1)begin
    error<=source_error?8'h01:core_error?8'h04:(accept&&!coords_ok)?8'h02:
     idle_count==IDLE_TIMEOUT-1?8'h20:!tx_ready?8'h10:8'h08;
    busy<=0;state<=IDLE;
   end else begin
    if(!end_seen)idle_count<=idle_count+1'b1;
    if(source_done)end_seen<=1;
    if(accept)begin
     inputs<=inputs+1'b1;scrc<=crc_byte(scrc,source_pixel);cooldown<=99;idle_count<=0;
     if(ix==W-1)begin ix<=0;iy<=iy+1'b1;end else ix<=ix+1'b1;
    end
    if(cv)begin
     outputs<=outputs+1'b1;pcrc<=crc_byte(pcrc,cp);
     if(ox==W-6)begin ox<=5;oy<=oy+1'b1;end else ox<=ox+1'b1;
    end
    case(state)
     HEADER:if(tx_ready)begin
      if(hi<28)hcrc<=crc_byte(hcrc,tx_byte);
      if(hi==31)state<=BODY;else hi<=hi+1'b1;
     end
     BODY:if(cv&&outputs==N-1)state<=DRAIN;
     DRAIN:if(inputs==W*H&&end_seen&&tx_ready)begin state<=FOOTER;fi<=0;end
     FOOTER:if(tx_ready)begin if(fi==19)state<=FINISH;else fi<=fi+1'b1;end
     FINISH:if(tx_ready)begin busy<=0;done<=1;state<=IDLE;end
     default:begin end
    endcase
   end
  end
 end
endmodule
