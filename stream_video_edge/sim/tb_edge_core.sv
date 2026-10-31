`timescale 1ns/1ps
module tb_edge_core #(parameter W=32,H=24);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,abort=0,valid=0,sof=0,view=0;
 reg[7:0]pixel=0;reg[9:0]x=0;reg[8:0]y=0;reg[31:0]fid=0;
 reg[10:0]threshold=128;
 wire ov,os,ol,oe,error;wire[7:0]op,raw,edgep;wire[9:0]ox;wire[8:0]oy;wire[31:0]of;
 edge_core #(W,H) dut(.clk(clk),.rst(rst),.abort(abort),.in_valid(valid),.in_pixel(pixel),
 .in_x(x),.in_y(y),.in_sof(sof),.in_frame_id(fid),.view_edge(view),
 .edge_threshold(threshold),.out_valid(ov),.out_pixel(op),.out_raw(raw),.out_edge(edgep),
 .out_x(ox),.out_y(oy),.out_frame_id(of),.out_sof(os),.out_eol(ol),.out_eof(oe),.error(error));
 localparam N=(W-10)*(H-10);
 reg[7:0]image[0:W*H-1],expected_raw[0:N-1],expected_edge[0:N-1];
 integer count=0,mode=0,frames=0,i,j;reg checking=0,saved_view=0;reg[31:0]saved_fid;
 string path,name;
 always @(posedge clk)begin #1;
  if(!rst&&!abort&&error)$fatal(1,"core error");
  if(ov)begin
   if(!checking||count>=N)$fatal(1,"unexpected pixel");
   if(raw!==expected_raw[count]||edgep!==expected_edge[count]||op!==(saved_view?expected_edge[count]:expected_raw[count]))
    $fatal(1,"pixels filter=%0d index=%0d raw=%h/%h edge=%h/%h",mode,count,raw,expected_raw[count],edgep,expected_edge[count]);
   if(ox!==5+count%(W-10)||oy!==5+count/(W-10)||of!==saved_fid||os!==(count==0)||ol!==(count%(W-10)==W-11)||oe!==(count==N-1))
    $fatal(1,"metadata index=%0d xy=%0d,%0d",count,ox,oy);
   count=count+1;
  end
 end
 task feed(input integer f,input bit gaps,input bit selected);
 begin
  mode=f;view=selected;threshold=128;
  saved_fid=100+frames;fid=saved_fid;saved_view=selected;count=0;checking=1;
  name=$sformatf("%s/edge_%0d.hex",path,f);$readmemh(name,expected_edge);
  for(i=0;i<W*H;i=i+1)begin
   @(negedge clk);valid=1;pixel=image[i];x=i%W;y=i/W;sof=(i==0);
   @(negedge clk);valid=0;sof=0;
   // Every non-SOF shadow configuration is deliberately illegal/different.
   view=!selected;threshold=2047;
   if(gaps)repeat((i*7)%5)@(negedge clk);
   if(!gaps&&i<W*H-1)begin
    // The next iteration's first negedge still gives one bubble in this
    // task; the separate burst below exercises every-clock operation.
   end
  end
  j=0;while(count<N&&j<300)begin @(negedge clk);j=j+1;end
  if(count!=N)$fatal(1,"incomplete output %0d/%0d",count,N);
  repeat(80)@(negedge clk);checking=0;frames=frames+1;
 end endtask
 task burst(input integer f);
 begin
  mode=f;view=1;threshold=128;
  saved_fid=100+frames;fid=saved_fid;saved_view=1;count=0;checking=1;
  name=$sformatf("%s/edge_%0d.hex",path,f);$readmemh(name,expected_edge);
  for(i=0;i<W*H;i=i+1)begin @(negedge clk);valid=1;pixel=image[i];x=i%W;y=i/W;sof=(i==0);end
  @(negedge clk);valid=0;sof=0;j=0;
  while(count<N&&j<300)begin @(negedge clk);j=j+1;end
  if(count!=N)$fatal(1,"burst incomplete");repeat(80)@(negedge clk);checking=0;frames=frames+1;
 end endtask
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"missing vectors");
  $readmemh({path,"/image.hex"},image);$readmemh({path,"/raw.hex"},expected_raw);
  repeat(5)@(negedge clk);rst=0;
  feed(1,1,0);feed(1,1,1);burst(1);
  // Abort after real output has begun, verify prefix then discard the frame.
  @(negedge clk);view=1;threshold=128;fid=999;
  saved_fid=999;saved_view=1;mode=1;count=0;checking=1;
  name=$sformatf("%s/edge_1.hex",path);$readmemh(name,expected_edge);
  for(i=0;i<16*W;i=i+1)begin @(negedge clk);valid=1;sof=(i==0);pixel=image[i];x=i%W;y=i/W;end
  @(negedge clk);valid=0;sof=0;abort=1;repeat(3)@(negedge clk);abort=0;
  if(count==0||count>=N)$fatal(1,"abort did not exercise partial output");checking=0;
  repeat(100)@(negedge clk);feed(1,1,1);
  @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;feed(1,0,0);
  $display("PASS tb_edge_core W=%0d H=%0d frames=%0d pixels=%0d",W,H,frames,N);$finish;
 end
 initial begin #200000000;$fatal(1,"watchdog");end
endmodule
