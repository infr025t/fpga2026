`timescale 1ns/1ps
module tb_guided_core #(parameter integer W=16,H=16,EXTRA_ALIGN=0);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,abort=0,iv=0;reg [7:0] pixel;reg [9:0] x;reg [8:0] y;
 reg sof=0,eol=0,eof=0;reg [31:0] fid;
 reg [10:0] eps=1024;reg [4:0] threshold=4;reg [9:0] gain=428;reg [1:0] mode=3;
 wire ov,os,ol,oe,err;wire [7:0] op,orr,ob;wire [9:0] ox;wire [8:0] oy;wire [31:0] ofid;
 guided_core #(W,H,EXTRA_ALIGN) dut(.clk(clk),.rst(rst),.abort(abort),.in_pixel(pixel),.in_valid(iv),.in_x(x),.in_y(y),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_frame_id(fid),.epsilon(eps),.threshold(threshold),.gain(gain),.view_mode(mode),.out_pixel(op),.out_raw(orr),.out_base(ob),.out_valid(ov),.out_x(ox),.out_y(oy),.out_sof(os),.out_eol(ol),.out_eof(oe),.out_frame_id(ofid),.arithmetic_error(err));
 localparam integer L=core_latency_pkg::L_CORE+EXTRA_ALIGN,Q=L+3,N=(W-8)*(H-8);
 initial if(L!=dut.L_CORE)$fatal(1,"bench/core latency mismatch");
 reg [7:0] image[0:W*H-1];reg [23:0] expected[0:N-1];
 reg qvalid[0:Q-1];reg [74:0] qdata[0:Q-1];
 integer cycle=0,outputs=0,frame_outputs=0,frames=0,flushes=0,first_cycle=0,sof_cycle=0;
 integer fd,scan,k,idx,epcfg,tcfg,gcfg,mcfg,schedule,cfg_count=0,flush_kind,position;
 integer max_run=0,current_run=0;reg [31:0] random_state=32'h1234abcd;
 string path,filename;
 task tick(input integer valid_token,input integer flush);
 integer j,due,xx,yy;
 begin
   @(negedge clk);iv=valid_token;rst=(flush==1);abort=(flush==2);
   if(!valid_token)begin pixel='x;x='x;y='x;fid='x;sof=0;eol=0;eof=0;end
   @(posedge clk);cycle=cycle+1;
   if(flush!=0)begin
     for(j=0;j<Q;j=j+1)qvalid[j]=0;
     flushes=flushes+1;
   end else if(valid_token)begin
     if(sof)sof_cycle=cycle;
     if(x>=8 && y>=8)begin
       xx=x-4;yy=y-4;due=(cycle+L)%Q;qvalid[due]=1;
       qdata[due]={fid,yy[8:0],xx[9:0],expected[(y-8)*(W-8)+(x-8)]};
     end
   end
   #1;due=cycle%Q;
   if(ov!==qvalid[due])$fatal(1,"core valid cycle=%0d got=%b expected=%b L=%0d",cycle,ov,qvalid[due],L);
   if(err!==0)$fatal(1,"unexpected arithmetic error cycle=%0d",cycle);
   if(ov)begin
     if({ofid,oy,ox,orr,ob,op}!==qdata[due])$fatal(1,"core data cycle=%0d xy=%0d,%0d got=%h expected=%h",cycle,ox,oy,{ofid,oy,ox,orr,ob,op},qdata[due]);
     if(os!==(ox==4 && oy==4) || ol!==(ox==W-5) || oe!==(ox==W-5 && oy==H-5))$fatal(1,"output marker mismatch");
     if(os)first_cycle=cycle;
     outputs=outputs+1;frame_outputs=frame_outputs+1;current_run=current_run+1;
     if(current_run>max_run)max_run=current_run;
   end else begin
     current_run=0;
     if(os!==0 || ol!==0 || oe!==0)$fatal(1,"marker without valid");
   end
   qvalid[due]=0;
 end endtask
 task send_frame(input integer frameid,input integer amount,input integer gaps);
 integer i,b;
 begin
   frame_outputs=0;first_cycle=0;
   for(i=0;i<amount;i=i+1)begin
     if(gaps!=0 && i>0)begin
       random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
       if(random_state[2:0]==0)repeat(random_state[5:3]+1)tick(0,0);
       if(i%W==0)repeat(113)tick(0,0);
     end
     pixel=image[i];x=i%W;y=i/W;fid=frameid;sof=(i==0);eol=(i%W==W-1);eof=(i==W*H-1);
     // Shadow requests may change after SOF; the active frame must retain its config.
     if(i==0)begin eps=epcfg;threshold=tcfg;gain=gcfg;mode=mcfg;end
     else begin eps=16;threshold=16;gain=512;mode=(mcfg+1)%4;end
     tick(1,0);
   end
 end endtask
 task finish_frame(input integer gaps);
 begin
   repeat(L)tick(0,0);
   if(frame_outputs!=N)$fatal(1,"frame count got=%0d expected=%0d",frame_outputs,N);
   if(gaps==0 && first_cycle-sof_cycle!=8*W+8+L)$fatal(1,"first-output formula mismatch");
   frames=frames+1;
 end endtask
 initial begin
   if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"missing vectors");
   for(k=0;k<Q;k=k+1)qvalid[k]=0;
   tick(0,1);tick(0,0);
   fd=$fopen({path,"/frames.txt"},"r");if(!fd)$fatal(1,"missing frame list");
   while(!$feof(fd))begin
     scan=$fscanf(fd,"%d %d %d %d %d %d\n",idx,epcfg,tcfg,gcfg,mcfg,schedule);
     if(scan!=6)$fatal(1,"bad frame list");
     filename=$sformatf("%s/image_%0d.hex",path,idx);$readmemh(filename,image);
     filename=$sformatf("%s/expected_%0d.hex",path,idx);$readmemh(filename,expected);
     send_frame(idx+1,W*H,schedule);finish_frame(schedule);cfg_count=cfg_count+1;
   end
   $fclose(fd);
   if(W<640)begin
     // Reset/abort after SOF, with coefficient division occupied, and at frame tail.
     for(flush_kind=1;flush_kind<=2;flush_kind=flush_kind+1)begin
       for(position=0;position<3;position=position+1)begin
         send_frame(1000+10*flush_kind+position,(position==0)?1:(position==1)?8*W+12:W*H,0);
         // Keep valid and the first/tail flags high: reset/abort must win.
         tick(1,flush_kind);repeat(L+2)tick(0,0);
         send_frame(2000+10*flush_kind+position,W*H,1);finish_frame(1);
       end
     end
   end
   if(max_run<W-8)$fatal(1,"II=1 output run not demonstrated");
   $display("PASS tb_guided_core W=%0d H=%0d align=%0d L=%0d frames=%0d configs=%0d pixels=%0d flushes=%0d max_run=%0d",W,H,EXTRA_ALIGN,L,frames,cfg_count,outputs,flushes,max_run);$finish;
 end
endmodule
module tb_guided_core_16;tb_guided_core #(16,16,0) test();endmodule
module tb_guided_core_17;tb_guided_core #(17,19,0) test();endmodule
module tb_guided_core_vga;tb_guided_core #(640,480,0) test();endmodule
module tb_guided_core_16_align;tb_guided_core #(16,16,1) test();endmodule
module tb_guided_core_17_align;tb_guided_core #(17,19,1) test();endmodule
module tb_guided_core_vga_align;tb_guided_core #(640,480,1) test();endmodule

// Fault injection targets the real full-width moments guard and coefficient input.
// At original coefficient (2,2), no final cropped output exists yet.
module tb_core_faults #(parameter integer EXTRA_ALIGN=0);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,abort=0,iv=0;reg [7:0] pixel=128;reg [9:0] x=0;reg [8:0] y=0;
 reg sof=0,eol=0,eof=0;wire ov,err;wire [7:0] op,orr,ob;
 wire [9:0] ox;wire [8:0] oy;wire os,ol,oe;wire [31:0] fid;
 guided_core #(16,16,EXTRA_ALIGN) dut(.clk(clk),.rst(rst),.abort(abort),.in_pixel(pixel),.in_valid(iv),.in_x(x),.in_y(y),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_frame_id(32'd19),.epsilon(11'd1024),.threshold(5'd4),.gain(10'd428),.view_mode(2'd3),.out_pixel(op),.out_raw(orr),.out_base(ob),.out_valid(ov),.out_x(ox),.out_y(oy),.out_sof(os),.out_eol(ol),.out_eof(oe),.out_frame_id(fid),.arithmetic_error(err));
 integer i,case_id,checked=0;reg injection_done=0;
 initial begin
   for(case_id=0;case_id<2;case_id=case_id+1)begin
     @(negedge clk);rst=1;abort=0;iv=0;
     repeat(2)@(posedge clk);
     @(negedge clk);rst=0;injection_done=0;
     fork
       begin
         for(i=0;i<256;i=i+1)begin
           @(negedge clk);iv=1;x=i%16;y=i/16;sof=(i==0);eol=(i%16==15);eof=(i==255);
         end
         @(negedge clk);iv=0;sof=0;eol=0;eof=0;
       end
       begin
         if(case_id==0)begin
           wait(dut.mom.vp[5] && dut.mom.xp[5]==4 && dut.mom.yp[5]==4);
           @(negedge clk);force dut.mom.next1=-23'sd1;
           @(posedge clk);#1;
           if(dut.me!==1 || err!==1 || ov!==0)$fatal(1,"early moments fault hidden by crop");
           release dut.mom.next1;
         end else begin
           wait(dut.mv && dut.mx==2 && dut.my==2);
           @(negedge clk);force dut.s1=13'd6375;force dut.s2=21'd0;
           @(posedge clk);#1;release dut.s1;release dut.s2;
           repeat(dut.coef.LATENCY)@(posedge clk);#1;
           if(dut.ce!==1 || err!==1 || ov!==0)$fatal(1,"negative variance fault hidden by crop");
         end
         checked=checked+1;
         abort=1;#1;if(err!==0 || ov!==0)$fatal(1,"abort must mask output and faults");
         injection_done=1;
       end
     join
     if(!injection_done)$fatal(1,"fault not injected");
     repeat(dut.L_CORE+2)begin @(posedge clk);#1;if(err!==0 || ov!==0)$fatal(1,"flush leaked token");end
   end
   $display("PASS tb_core_faults align=%0d early_faults=%0d",EXTRA_ALIGN,checked);$finish;
 end
 initial begin #100000;$fatal(1,"fault bench timeout");end
endmodule
module tb_core_faults_0;tb_core_faults #(0) test();endmodule
module tb_core_faults_1;tb_core_faults #(1) test();endmodule
