`timescale 1ns/1ps
module tb_display_path;
 localparam W=32,H=24;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,source_valid=0,source_done=0,edge_view=0,filter_id=0;
 reg[7:0]source_pixel=0;reg[9:0]source_x=0;reg[8:0]source_y=0;
 wire v,d,e;wire[7:0]p,raw;wire[9:0]x;wire[8:0]y;
 wire sink_ready,sink_done,sink_busy,initialized,bg;wire[7:0]sink_error;
 wire[31:0]received,painted,ic,oc,frames;wire[7:0]lcd_data;wire lcd_cs,lcd_rs,lcd_wr,lcd_rd,lcd_rst,lcd_bl;
 wire[127:0]snapshot_block;wire[31:0]snapshot_status;reg[10:0]read_command=0;
 video_lcd_sink #(.W(W),.H(H),.PW(W+16),.PH(H)) sink(
 .clk(clk),.rst(rst),.start(start),.crop_edge(edge_view),
 .source_valid(v),.source_pixel(p),.source_x(x),.source_y(y),.source_done(d),.source_error(e),
 .ready(sink_ready),.busy(sink_busy),.done(sink_done),.error(sink_error),.initialized(initialized),.background_done(bg),
 .received(received),.painted(painted),.input_crc(ic),.output_crc(oc),.frames(frames),
 .lcd_data(lcd_data),.lcd_cs_n(lcd_cs),.lcd_rs(lcd_rs),.lcd_wr_n(lcd_wr),.lcd_rd_n(lcd_rd),.lcd_reset_n(lcd_rst),.lcd_bl(lcd_bl));
 video_snapshot #(.W(W),.H(H),.BLOCK_WORDS(8)) snap(.clk(clk),.rst(rst),.start(start),.pixel_valid(v),
 .pixel(p),.raw_pixel(raw),.x(x),.y(y),.source_done(d),.crop_edge(edge_view),
 .read_command(read_command),.block_data(snapshot_block),.status(snapshot_status));

 video_core_adapter #(W,H) dut(.clk(clk),.rst(rst),.start(start),.edge_view(edge_view),.filter_id(filter_id),
 .source_valid(source_valid),.source_pixel(source_pixel),.source_x(source_x),.source_y(source_y),.source_done(source_done),
 .out_valid(v),.out_pixel(p),.out_raw(raw),.out_x(x),.out_y(y),.out_done(d),.error(e));
 reg[7:0]image[0:W*H-1],expected[0:W*H-1];reg[1023:0]folder;
 integer frame,xx,yy,n=0,ew,eh,timeout=0,b,j,address,ix,iy,words,shown=0;reg toggle=0;reg[15:0]wanted;reg finished=0;
 reg pixel_transaction=0,clear_transaction=0,clear_second=0;integer clear_words=0;
 reg second=0;reg[7:0]high_byte;
 always @(posedge clk)if(rst)pixel_transaction<=0;else if(sink.bus.in_ready && sink.bus.in_valid)
   begin pixel_transaction<=(sink.painter.state==3 && sink.state==5);clear_transaction<=(sink.painter.state==3 && sink.state==2);end
 always @(posedge lcd_wr)if(!rst && !lcd_cs && clear_transaction)begin
  if(lcd_data!==0)$fatal(1,"background clear not black");
  if(clear_second)clear_words=clear_words+1;
  clear_second=!clear_second;
 end
 always @(posedge lcd_wr)if(!rst && !lcd_cs && pixel_transaction)begin
  if(!lcd_rs)$fatal(1,"pixel RS low");
  if(!second)begin high_byte=lcd_data;second=1;end
  else begin
   wanted={expected[shown][7:3],expected[shown][7:2],expected[shown][7:3]};
   if({high_byte,lcd_data}!==wanted)$fatal(1,"LCD bus mismatch frame=%0d shown=%0d got=%h wanted=%h",frame,shown,{high_byte,lcd_data},wanted);
   second=0;shown=shown+1;
  end
 end
 always @(posedge clk)if(!rst)begin
  if(sink_error)$fatal(1,"LCD sink error %h",sink_error);
  if(v)begin
   if(x!==n%ew || y!==n/ew || p!==expected[n] || raw!==image[(edge_view?(n/ew+5):n/ew)*W+(edge_view?(n%ew+5):n%ew)])
    $fatal(1,"path mismatch frame=%0d n=%0d xy=%0d,%0d got=%0d ref=%0d raw=%0d",frame,n,x,y,p,expected[n],raw);
   n=n+1;
  end
  if(e)$fatal(1,"core error");
  if(d)begin if(n!=ew*eh)$fatal(1,"early done frame=%0d n=%0d",frame,n);finished=1;end
 end
 initial begin
  if(!$value$plusargs("VECTORS=%s",folder))$fatal(1,"vectors missing");
  $readmemh({folder,"/image.hex"},image);
  repeat(4)@(negedge clk);rst=0;
  for(frame=0;frame<4;frame=frame+1)begin
   edge_view=frame[1];filter_id=frame[0];ew=edge_view?W-10:W;eh=edge_view?H-10:H;
   if(!edge_view)$readmemh({folder,"/image.hex"},expected);
   else if(filter_id)$readmemh({folder,"/edge_1.hex"},expected,0,(W-10)*(H-10)-1);
   else $readmemh({folder,"/edge_0.hex"},expected,0,(W-10)*(H-10)-1);
   @(negedge clk);wait(sink_ready);@(negedge clk);
   if(clear_words!=(frame<2?1:2)*(W+16)*H)$fatal(1,"mode switch retained stale RAW border: clear pixels=%0d frame=%0d",clear_words,frame);
   n=0;shown=0;finished=0;start=1;@(negedge clk);start=0;
   for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
    source_valid=1;source_x=xx;source_y=yy;source_pixel=image[yy*W+xx];
    @(negedge clk);source_valid=0;repeat(99+(xx+3*yy)%4)@(negedge clk);
   end
   source_done=1;@(negedge clk);source_done=0;
   timeout=0;while(!finished&&timeout<1000)begin @(negedge clk);timeout=timeout+1;end
   if(!finished)$fatal(1,"drain timeout");
   wait(sink_ready);@(negedge clk);
   if(received!=ew*eh||painted!=ew*eh||shown!=ew*eh||ic!=oc||second)$fatal(1,"sink final count/CRC frame=%0d rx=%0d tx=%0d shown=%0d expected=%0d ic=%h oc=%h second=%0d",frame,received,painted,shown,ew*eh,ic,oc,second);
   words=ew*eh/4;
   if(snapshot_status[31:29]||!snapshot_status[17]||snapshot_status[16:0]!=words)$fatal(1,"snapshot final state %h",snapshot_status);
   for(b=0;b<(words+7)/8;b=b+1)begin
    toggle=!toggle;read_command={toggle,10'(b)};
    wait(snapshot_status[20]==toggle && !snapshot_status[19]);@(negedge clk);
    for(j=0;j<8;j=j+1)begin
     address=b*8+j;ix=2*(address%(ew/2))+1;iy=2*(address/(ew/2));
     wanted=address<words?{image[(iy+(edge_view?5:0))*W+ix+(edge_view?5:0)],expected[iy*ew+ix]}:16'd0;
     if(snapshot_block[16*j+:16]!==wanted)$fatal(1,"snapshot pair/partial block mismatch %0d/%0d got=%h expected=%h",b,j,snapshot_block[16*j+:16],wanted);
    end
   end
   repeat(8)@(negedge clk);
  end
  $display("PASS tb_display_path all four RAW/EDGE x guided/gaussian modes; gaps, full counts, EOF drain");$finish;
 end
endmodule

// Only initialization delays are bypassed; real window and bus engines are tested.
module nt35510_init #(parameter CLK_HZ=100000000)(
 input wire clk,rst,word_ready,word_done,output wire word_valid,output wire[15:0]word,output wire word_rs,lcd_reset_n,init_done);
 assign word_valid=0;assign word=0;assign word_rs=0;assign lcd_reset_n=!rst;assign init_done=!rst;
endmodule
