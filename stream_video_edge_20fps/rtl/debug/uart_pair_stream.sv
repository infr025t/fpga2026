`timescale 1ns/1ps
// Passive test-only 12Mbaud paired overview. No backpressure or correction path.
module uart_pair_stream #(parameter W=640,H=480,DEPTH=1024)(
 input wire clk,rst,start,source_valid,input wire[7:0]pixel,other,
 input wire[9:0]x,input wire[8:0]y,input wire source_done,
 output wire uart_txd,output reg[31:0]dropped,packets
);
 localparam WORDS=(W/4)*(H/4),N=2*WORDS,AW=$clog2(DEPTH);
 localparam IDLE=0,HEADER=1,CAPTURE=2,TRAILER=3;
 reg[1:0]state;reg[5:0]hi;reg[2:0]fi;
 reg[31:0]sequence_id,active_id,ticks,active_tick,hcrc,pcrc,tail_crc,samples;
 reg pending;reg[7:0]pending_byte;
 (* ram_style="distributed" *)reg[7:0]queue[0:DEPTH-1];
 reg[AW-1:0]wp,rp;reg[AW:0]used;
 wire tx_ready;wire tx_valid=used!=0;wire pop=tx_valid&&tx_ready;
 reg enq;reg[7:0]byte_in;
 wire push=enq&&(used<DEPTH||pop);
 wire selected=source_valid&&x[1:0]==3&&y[1:0]==0;
 uart_fast_tx tx(.clk(clk),.rst(rst),.valid(tx_valid),.data(queue[rp]),.ready(tx_ready),.tx(uart_txd));
 function automatic[31:0]crc_byte(input[31:0]crc,input[7:0]value);
 reg[31:0]c;integer k;begin c=crc^value;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end endfunction
 function automatic[7:0]header_byte(input[5:0]n);
 reg[31:0]v;begin v=0;case(n)
 0:header_byte="Y";1:header_byte="V";2:header_byte="P";3:header_byte="A";
 4:header_byte="I";5:header_byte="R";6:header_byte="1";7:header_byte="!";
 8,9,10,11:header_byte=active_id>>(8*(n-8));
 12,13:begin v=W/4;header_byte=v>>(8*(n-12));end
 14,15:begin v=H/4;header_byte=v>>(8*(n-14));end
 16,17,18,19:header_byte=N>>(8*(n-16));
 20,21,22,23:header_byte=active_tick>>(8*(n-20));
 24,25,26,27:header_byte=dropped>>(8*(n-24));
 28,29,30,31:header_byte=(~hcrc)>>(8*(n-28));
 default:header_byte=0;endcase end endfunction
 always @*begin
  enq=0;byte_in=0;
  case(state)
   HEADER:begin enq=1;byte_in=header_byte(hi);end
   CAPTURE:if(pending)begin enq=1;byte_in=pending_byte;end
    else if(selected)begin enq=1;byte_in=pixel;end
   TRAILER:begin enq=1;byte_in=tail_crc>>(8*fi);end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;hi<=0;fi<=0;sequence_id<=0;active_id<=0;ticks<=0;active_tick<=0;
   hcrc<=32'hffffffff;pcrc<=32'hffffffff;tail_crc<=0;samples<=0;pending<=0;pending_byte<=0;
   wp<=0;rp<=0;used<=0;dropped<=0;packets<=0;
  end else begin
   ticks<=ticks+1'b1;
   if(push)begin queue[wp]<=byte_in;wp<=wp+1'b1;end
   if(pop)rp<=rp+1'b1;
   case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:begin end endcase
   if(start)begin
    if(state!=IDLE)dropped<=dropped+1'b1;
    state<=HEADER;hi<=0;fi<=0;sequence_id<=sequence_id+1'b1;active_id<=sequence_id+1'b1;
    active_tick<=ticks;hcrc<=32'hffffffff;pcrc<=32'hffffffff;samples<=0;pending<=0;
   end else if((enq&&!push)||(selected&&state==HEADER)||(selected&&pending))begin
    state<=IDLE;pending<=0;dropped<=dropped+1'b1;
   end else case(state)
    HEADER:if(push)begin
     if(hi<28)hcrc<=crc_byte(hcrc,byte_in);
     if(hi==31)state<=CAPTURE;else hi<=hi+1'b1;
    end
    CAPTURE:begin
     if(push)begin
      pcrc<=crc_byte(pcrc,byte_in);
      if(pending)begin
       pending<=0;
       if(samples==WORDS)begin tail_crc<=~crc_byte(pcrc,byte_in);fi<=0;state<=TRAILER;end
      end
      else begin pending<=1;pending_byte<=other;samples<=samples+1'b1;end
     end
     if(source_done)begin
      // A valid packet finishes after its last selected row, before native EOF.
      // EOF here means the selected overview was incomplete.
      dropped<=dropped+1'b1;state<=IDLE;pending<=0;
     end
    end
    TRAILER:if(push)begin
     if(fi==3)begin state<=IDLE;packets<=packets+1'b1;end else fi<=fi+1'b1;
    end
    default:begin end
   endcase
  end
 end
 initial if(W%4||H%4||DEPTH<512||(DEPTH&(DEPTH-1)))$fatal(1,"invalid paired UART geometry");
endmodule
