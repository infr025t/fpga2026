`timescale 1ns/1ps
module windows_case #(parameter integer W=16,H=16);
 reg clk=0; always #5 clk=~clk;
 reg rst=1,abort=0,iv=0,biv=0;
 reg [7:0] pixel=0;
 reg [9:0] x=0; reg [8:0] y=0; reg sof=0;
 reg [31:0] fid=0;
 reg [11:0] a=0; reg [15:0] b=0;
 wire mv,bv,rv,err,merr;
 wire [12:0] s1; wire [20:0] s2; wire [7:0] center,align;
 wire [11:0] abar; wire [15:0] bbar;
 wire [9:0] mx,bx,rx; wire [8:0] my,by,ry;
 wire [31:0] mf,bf,rf; wire [39:0] rowdata;
 moments5 #(W,H) mom(.clk(clk),.rst(rst),.abort(abort),.in_valid(iv),.in_pixel(pixel),
   .in_x(x),.in_y(y),.in_sof(sof),.in_frame_id(fid),.out_valid(mv),.out_s1(s1),.out_s2(s2),
   .out_center(center),.out_x(mx),.out_y(my),.out_frame_id(mf),.range_error(merr));
 coefficient_box5 #(W,H) box(.clk(clk),.rst(rst),.abort(abort),.in_valid(biv),
   .in_a(a),.in_b(b),.in_center(pixel),.in_x(x),.in_y(y),.in_sof(x==2 && y==2),
   .in_frame_id(fid),.out_valid(bv),.out_abar(abar),.out_bbar(bbar),.out_align(align),
   .out_x(bx),.out_y(by),.out_frame_id(bf),.range_error(err));
 row_window5 #(W,H,8) rows(.clk(clk),.rst(rst),.abort(abort),.in_valid(iv),.in_data(pixel),
   .in_x(x),.in_y(y),.in_sof(sof),.in_frame_id(fid),.out_valid(rv),.out_rows(rowdata),
   .out_x(rx),.out_y(ry),.out_frame_id(rf));
 integer pixels[0:W*H-1],exp_s1[0:W*H-1],exp_s2[0:W*H-1];
 integer ca[0:W*H-1],cb[0:W*H-1],ea[0:W*H-1],eb[0:W*H-1];
 integer mdue[0:63],mi[0:63],mframe[0:63],bdue[0:63],bi[0:63],bframe[0:63];
 integer rdue[0:63],ri[0:63],rframe[0:63];
 integer mh=0,mt=0,bh=0,bt=0,rh=0,rt=0,cycle=0,mc=0,bc=0,rc=0,bank_checks=0;
 integer m_before,b_before,i,j,d,idx,wanted,got,casefd,fd,status,caseno=0,mode;
 integer frames=0,flushes=0;
 reg [31:0] random_state=32'hd31c4907;
 string directory,filename;

 task bank_check(input [4:0] we,input [4:0] re,input valid);
   integer k,nw,nr;
   begin
     nw=0;nr=0;
     for(k=0;k<5;k=k+1)begin nw=nw+we[k];nr=nr+re[k];end
     if ((we & re)!==0 || nw!=(valid?1:0) || nr!=(valid?4:0))
       $fatal(1,"bank conflict/port count we=%b re=%b valid=%b",we,re,valid);
     bank_checks=bank_checks+1;
   end
 endtask

 always @(posedge clk) begin
   cycle=cycle+1;
   bank_check(rows.bank_write_enable,rows.bank_read_enable,iv && !rst && !abort);
   bank_check(mom.rows.bank_write_enable,mom.rows.bank_read_enable,iv && !rst && !abort);
   bank_check(box.rows.bank_write_enable,box.rows.bank_read_enable,biv && !rst && !abort);
   if(rst || abort)begin mh=0;mt=0;bh=0;bt=0;rh=0;rt=0;end
   else begin
     if(iv) begin
       rdue[rt%64]=cycle+rows.LATENCY;ri[rt%64]=y*W+x;rframe[rt%64]=fid;rt=rt+1;
       if(x>=4 && y>=4)begin
         mdue[mt%64]=cycle+mom.LATENCY;mi[mt%64]=(y-2)*W+x-2;mframe[mt%64]=fid;mt=mt+1;
       end
     end
     if(biv && x>=6 && y>=6)begin
       bdue[bt%64]=cycle+box.LATENCY;bi[bt%64]=(y-2)*W+x-2;bframe[bt%64]=fid;bt=bt+1;
     end
   end
   #1;
   if(rv !== (rh<rt && rdue[rh%64]==cycle)) $fatal(1,"row valid latency cycle=%0d",cycle);
   if(mv !== (mh<mt && mdue[mh%64]==cycle)) $fatal(1,"mom valid latency cycle=%0d",cycle);
   if(bv !== (bh<bt && bdue[bh%64]==cycle)) $fatal(1,"box valid latency cycle=%0d",cycle);
   if(err !== 0 || merr !== 0) $fatal(1,"arithmetic error cycle=%0d",cycle);
   if(rv)begin
     idx=ri[rh%64];
     if(rx!==idx%W || ry!==idx/W || rf!==rframe[rh%64]) $fatal(1,"row metadata");
     for(d=0;d<5;d=d+1)begin
       wanted=(idx/W>=4-d)?pixels[idx-(4-d)*W]:0;
       if(rowdata[d*8+:8]!==wanted[7:0]) $fatal(1,"row order/old RAM leak idx=%0d row=%0d",idx,d);
     end
     rh=rh+1;rc=rc+1;
   end
   if(mv)begin
     idx=mi[mh%64];
     if(mx!==idx%W || my!==idx/W || mf!==mframe[mh%64] || s1!==exp_s1[idx] || s2!==exp_s2[idx] || center!==pixels[idx])
       $fatal(1,"mom data idx=%0d xy=%0d,%0d s1=%0d/%0d s2=%0d/%0d center=%0d/%0d",idx,mx,my,s1,exp_s1[idx],s2,exp_s2[idx],center,pixels[idx]);
     mh=mh+1;mc=mc+1;
   end
   if(bv)begin
     idx=bi[bh%64];
     if(bx!==idx%W || by!==idx/W || bf!==bframe[bh%64] || abar!==ea[idx] || bbar!==eb[idx] || align!==pixels[idx])
       $fatal(1,"box data idx=%0d xy=%0d,%0d A=%0d/%0d b=%0d/%0d align=%0d/%0d",idx,bx,by,abar,ea[idx],bbar,eb[idx],align,pixels[idx]);
     bh=bh+1;bc=bc+1;
   end
 end

 task idle(input integer clocks);
   integer k;
   begin
     for(k=0;k<clocks;k=k+1)begin
       @(negedge clk);iv=0;biv=0;pixel='x;a='x;b='x;x='x;y='x;sof=0;
     end
   end
 endtask
 task send_prefix(input integer count,input integer gaps);
   integer k,g;
   begin
     fid=fid+1;
     for(k=0;k<count;k=k+1)begin
       if(gaps!=0)begin
         random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
         if(k%W==0 && k>0) idle(41);
         if(random_state[2:0]==0) idle(1+random_state[4:3]);
       end
       @(negedge clk);iv=1;x=k%W;y=k/W;pixel=pixels[k];sof=k==0;
       biv=(x>=2 && x<W-2 && y>=2 && y<H-2);a=ca[k];b=cb[k];
     end
   end
 endtask
 task flush(input integer use_abort);
   begin
     // Keep input valid while flushing; reset/abort must suppress RAM and output.
     @(negedge clk);if(use_abort!=0)abort=1;else rst=1;
     @(negedge clk);iv=0;biv=0;abort=0;rst=0;
     idle(32);flushes=flushes+1;
   end
 endtask
 task complete_frame(input integer gaps);
   begin
     m_before=mc;b_before=bc;
     send_prefix(W*H,gaps);idle(32);@(negedge clk);
     if(mc-m_before!=(W-4)*(H-4) || bc-b_before!=(W-8)*(H-8)) $fatal(1,"crop/count");
     if(mh!=mt || bh!=bt || rh!=rt) $fatal(1,"undrained queue");
     frames=frames+1;
   end
 endtask
 initial begin
   if(!$value$plusargs("VECTORS=%s",directory)) $fatal(1,"missing vectors");
   casefd=$fopen({directory,"/cases.txt"},"r");if(!casefd)$fatal(1,"cases missing");
   repeat(3)@(negedge clk);rst=0;
   while($fscanf(casefd,"%s",filename)==1)begin
     fd=$fopen({directory,"/",filename},"r");if(!fd)$fatal(1,"file missing");
     for(i=0;i<W*H;i=i+1)begin
       status=$fscanf(fd,"%d %d %d %d %d %d %d",pixels[i],exp_s1[i],exp_s2[i],ca[i],cb[i],ea[i],eb[i]);
       if(status!=7)$fatal(1,"short vectors");
     end
     $fclose(fd);
     complete_frame(0);
     if(W<640)begin
       complete_frame(1);
       if(caseno==0)begin
         // Warmup and occupied valid arithmetic; stale RAM survives all flushes.
         send_prefix(2*W+3,1);flush(1);complete_frame(1);
         send_prefix(2*W+3,0);flush(0);complete_frame(0);
         send_prefix(9*W+9,0);flush(1);complete_frame(1);
         send_prefix(9*W+9,1);flush(0);complete_frame(0);
       end
     end
     caseno=caseno+1;
   end
   if(caseno==0)$fatal(1,"empty cases");
   $display("PASS tb_windows W=%0d H=%0d frames=%0d flushes=%0d moments=%0d box=%0d rows=%0d bank_checks=%0d latencies=%0d,%0d,%0d",W,H,frames,flushes,mc,bc,rc,bank_checks,rows.LATENCY,mom.LATENCY,box.LATENCY);
   $finish;
 end
endmodule
module tb_windows_16; windows_case #(16,16) test(); endmodule
module tb_windows_17; windows_case #(17,19) test(); endmodule
module tb_windows_vga; windows_case #(640,480) test(); endmodule

// Independent literal boundary/error checks, separate from model vectors.
module tb_window_ranges;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,abort=0,iv=0;
 reg [9:0] x=0;reg [8:0] y=0;
 reg [11:0] a=0;reg [15:0] b=0;
 wire ov,err;wire [11:0] oa;wire [15:0] ob;
 wire [7:0] oi;wire [9:0] ox;wire [8:0] oy;wire [31:0] ofid;
 integer frame=0,count=0,total=0,k,f;
 reg expected_error;
 reg [11:0] expected_a;reg [15:0] expected_b;
 coefficient_box5 #(16,16) dut(.clk(clk),.rst(rst),.abort(abort),.in_valid(iv),
   .in_a(a),.in_b(b),.in_center(8'd173),.in_x(x),.in_y(y),.in_sof(x==2 && y==2),
   .in_frame_id(frame),.out_valid(ov),.out_abar(oa),.out_bbar(ob),.out_align(oi),
   .out_x(ox),.out_y(oy),.out_frame_id(ofid),.range_error(err));
 always @(posedge clk)begin
   #1;
   if(err && !ov)$fatal(1,"error leaked into bubble");
   if(ov)begin
     if(err!==expected_error || oa!==expected_a || ob!==expected_b || oi!==173 || ofid!==frame ||
       ox!==4+count%8 || oy!==4+count/8)
       $fatal(1,"range literal frame=%0d count=%0d A=%0d b=%0d error=%b expected=%b",frame,count,oa,ob,err,expected_error);
     count=count+1;total=total+1;
   end
 end
 initial begin
   repeat(3)@(negedge clk);rst=0;
   for(f=0;f<3;f=f+1)begin
     frame=f+1;count=0;expected_error=f!=0;
     expected_a=(f==0)?4092:0;expected_b=(f==0)?65280:0;
     for(k=0;k<144;k=k+1)begin
       @(negedge clk);iv=1;x=2+k%12;y=2+k/12;
       // Legal independent maxima; then A over ledger; then b over ledger.
       a=(f==0)?4092:((f==1)?4095:0);b=(f==0)?65280:((f==2)?65535:0);
     end
     @(negedge clk);iv=0;
     repeat(32)@(negedge clk);
     if(count!=64)$fatal(1,"range crop count");
   end
   $display("PASS tb_window_ranges literals=%0d legal_max=64 flagged_A=64 flagged_b=64",total);$finish;
 end
endmodule
