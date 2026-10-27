`timescale 1ns/1ps
module tb_core_stages;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,abort=0,iv=0;
 reg [12:0] s1;reg [20:0] s2;reg [10:0] eps;reg [7:0] center;
 reg [11:0] abar;reg [15:0] bbar;reg [7:0] align_pixel;
 reg [7:0] raw;reg [15:0] base;reg [4:0] threshold;reg [9:0] gain;reg [1:0] mode;
 reg [9:0] x;reg [8:0] y;reg [31:0] fid;
 wire cv,ce,rv,re,ev,ee;wire [11:0] ca;wire [15:0] cb,rb;
 wire [7:0] cc,rc,ep,er,eb;wire [9:0] cx,rx,ex;wire [8:0] cy,ry,ey;wire [31:0] cf,rf,ef;
 coefficient5 c(.clk(clk),.rst(rst),.abort(abort),.in_valid(iv),.in_s1(s1),.in_s2(s2),.epsilon(eps),.in_center(center),.in_x(x),.in_y(y),.in_frame_id(fid),.out_valid(cv),.out_a(ca),.out_b(cb),.out_center(cc),.out_x(cx),.out_y(cy),.out_frame_id(cf),.range_error(ce));
 reconstruct r(.clk(clk),.rst(rst),.abort(abort),.in_valid(iv),.in_abar(abar),.in_bbar(bbar),.in_align(align_pixel),.in_x(x),.in_y(y),.in_frame_id(fid),.out_valid(rv),.out_base_q8(rb),.out_align(rc),.out_x(rx),.out_y(ry),.out_frame_id(rf),.range_error(re));
 detail_enhance e(.clk(clk),.rst(rst),.abort(abort),.in_valid(iv),.in_base_q8(base),.in_align(raw),.threshold(threshold),.gain(gain),.view_mode(mode),.in_x(x),.in_y(y),.in_frame_id(fid),.out_valid(ev),.out_pixel(ep),.out_raw(er),.out_base(eb),.out_x(ex),.out_y(ey),.out_frame_id(ef),.range_error(ee));
 localparam integer Q=128;
 reg qc[0:Q-1],qr[0:Q-1],qe[0:Q-1];
 reg [87:0] dc[0:Q-1];reg [74:0] dr[0:Q-1];reg [74:0] de[0:Q-1];
 integer cycle=0,n=0,k,fd,scan,pass_id,countc=0,countr=0,counte=0,flushes=0;
 integer a0,b0,error0,base0,pixel0,rounded0;
 string path;
 task tick(input integer valid_token,input integer flush);
 integer j,due;
 begin
   @(negedge clk);iv=valid_token;rst=(flush==1);abort=(flush==2);
   if(valid_token)begin x=n%640;y=n%480;fid=32'hfedc0000+n;end
   @(posedge clk);cycle=cycle+1;
   if(flush!=0)begin
     for(j=0;j<Q;j=j+1)begin qc[j]=0;qr[j]=0;qe[j]=0;end
     flushes=flushes+1;
   end else if(valid_token)begin
     due=(cycle+c.LATENCY)%Q;qc[due]=1;dc[due]={error0[0],fid,y,x,center,a0[11:0],b0[15:0]};
     due=(cycle+r.LATENCY)%Q;qr[due]=1;dr[due]={fid,y,x,align_pixel,base0[15:0]};
     rounded0=(base+128)>>8;
     due=(cycle+e.LATENCY)%Q;qe[due]=1;de[due]={fid,y,x,raw,rounded0[7:0],pixel0[7:0]};
   end
   #1;due=cycle%Q;
   if(cv!==qc[due])$fatal(1,"coefficient valid cycle=%0d",cycle);
   if(rv!==qr[due])$fatal(1,"reconstruct valid cycle=%0d",cycle);
   if(ev!==qe[due])$fatal(1,"enhancement valid cycle=%0d",cycle);
   if(cv)begin
     if({ce,cf,cy,cx,cc,ca,cb}!==dc[due])$fatal(1,"coefficient data cycle=%0d got=%h expected=%h",cycle,{ce,cf,cy,cx,cc,ca,cb},dc[due]);
     countc=countc+1;
   end else if(ce!==0)$fatal(1,"coefficient invalid error");
   if(rv)begin
     if(re!==0 || {rf,ry,rx,rc,rb}!==dr[due])$fatal(1,"reconstruction data cycle=%0d got=%h expected=%h",cycle,{rf,ry,rx,rc,rb},dr[due]);
     countr=countr+1;
   end else if(re!==0)$fatal(1,"reconstruction invalid error");
   if(ev)begin
     if(ee!==0 || {ef,ey,ex,er,eb,ep}!==de[due])$fatal(1,"enhancement data cycle=%0d got=%h expected=%h",cycle,{ef,ey,ex,er,eb,ep},de[due]);
     counte=counte+1;
   end else if(ee!==0)$fatal(1,"enhancement invalid error");
   qc[due]=0;qr[due]=0;qe[due]=0;
 end endtask
 initial begin
   if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"missing vectors");
   for(k=0;k<Q;k=k+1)begin qc[k]=0;qr[k]=0;qe[k]=0;end
   tick(0,1);tick(0,0);
   for(pass_id=0;pass_id<2;pass_id=pass_id+1)begin
     fd=$fopen({path,"/stages.txt"},"r");if(!fd)$fatal(1,"missing stage file");
     while(!$feof(fd))begin
       scan=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",s1,s2,eps,center,a0,b0,error0,abar,bbar,align_pixel,base0,raw,base,threshold,gain,mode,pixel0);
       if(scan!=17)$fatal(1,"bad stage vector");
       n=n+1;tick(1,0);
       if(pass_id==1 && n%11==0)repeat(3)tick(0,0);
       if(pass_id==1 && n%701==0)begin tick(0,1+(n%2));repeat(c.LATENCY+2)tick(0,0);end
     end
     $fclose(fd);repeat(c.LATENCY+3)tick(0,0);
   end
   $display("PASS tb_core_stages coefficient=%0d reconstruct=%0d enhance=%0d flushes=%0d latency=%0d/%0d/%0d",countc,countr,counte,flushes,c.LATENCY,r.LATENCY,e.LATENCY);$finish;
 end
endmodule
