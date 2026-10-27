`timescale 1ns/1ps
module tb_resource_exchange;
 parameter integer W=16,H=16;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,abort=0,iv=0,cv=0,sof=0,csof=0;
 reg [7:0] pixel=0,center=0;
 reg [11:0] a=0;reg [15:0] b=0;
 reg [9:0] x=0,cx=0;reg [8:0] y=0,cy=0;reg [31:0] fid=0;
 wire [1:0] mv,bv,me,be;
 wire [12:0] s1[0:1];wire [20:0] s2[0:1];wire [7:0] mc[0:1],bc[0:1];
 wire [9:0] mx[0:1],bx[0:1];wire [8:0] my[0:1],by[0:1];
 wire [31:0] mf[0:1],bf[0:1];wire [11:0] ba[0:1];wire [15:0] bb[0:1];
 moments5 #(W,H) ma(clk,rst,abort,iv,pixel,x,y,sof,fid,mv[0],s1[0],s2[0],mc[0],mx[0],my[0],mf[0],me[0]);
 moments_store_square #(W,H) mb(clk,rst,abort,iv,pixel,x,y,sof,fid,mv[1],s1[1],s2[1],mc[1],mx[1],my[1],mf[1],me[1]);
 coefficient_box5 #(W,H) ca(clk,rst,abort,cv,a,b,center,cx,cy,csof,fid,bv[0],ba[0],bb[0],bc[0],bx[0],by[0],bf[0],be[0]);
 coefficient_box_queue #(W,H) cb(clk,rst,abort,cv,a,b,center,cx,cy,csof,fid,bv[1],ba[1],bb[1],bc[1],bx[1],by[1],bf[1],be[1]);
 function integer pix(input integer xx,yy,ff); pix=(xx*37+yy*71+xx*yy*3+ff*19)&255;endfunction
 function integer coef_a(input integer xx,yy,ff);coef_a=(xx*91+yy*173+xx*yy*7+ff*31)%4093;endfunction
 function integer coef_b(input integer xx,yy,ff);coef_b=(xx*2003+yy*701+xx*yy*113+ff*997)%65281;endfunction
 integer cycle=0,acount=0,bcount=0,k,i,j,z,ex1,ex2,exa,exb;
 reg [12:0] ap=0,bp=0;
 integer axp[0:12],ayp[0:12],afp[0:12],bxp[0:12],byp[0:12],bfp[0:12];
 always @(posedge clk)begin
   cycle=cycle+1;
   for(k=12;k>0;k=k-1)begin
     ap[k]=ap[k-1];bp[k]=bp[k-1];axp[k]=axp[k-1];ayp[k]=ayp[k-1];afp[k]=afp[k-1];
     bxp[k]=bxp[k-1];byp[k]=byp[k-1];bfp[k]=bfp[k-1];
   end
   ap[0]=iv && x>=4 && y>=4;bp[0]=cv && cx>=6 && cy>=6;
   axp[0]=x-2;ayp[0]=y-2;afp[0]=fid;bxp[0]=cx-2;byp[0]=cy-2;bfp[0]=fid;
   if(rst || abort)begin ap=0;bp=0;end
   #1;
   if(mv!=={2{ap[9]}} || bv!=={2{bp[12]}}) $fatal(1,"valid/latency cycle %0d mv=%b bv=%b expected=%b,%b",cycle,mv,bv,ap[9],bp[12]);
   if(ap[9])begin
     ex1=0;ex2=0;
     for(i=-2;i<=2;i=i+1)for(j=-2;j<=2;j=j+1)begin
       z=pix(axp[9]+i,ayp[9]+j,afp[9]);ex1=ex1+z;ex2=ex2+z*z;
     end
     for(i=0;i<2;i=i+1)if(me[i]!==0 || s1[i]!==ex1[12:0] || s2[i]!==ex2[20:0] ||
       mc[i]!==pix(axp[9],ayp[9],afp[9]) || mx[i]!==axp[9] || my[i]!==ayp[9] || mf[i]!==afp[9])
       $fatal(1,"moments mismatch variant %0d cycle %0d xy=%0d,%0d",i,cycle,axp[9],ayp[9]);
     acount=acount+1;
   end
   if(bp[12])begin
     exa=0;exb=0;
     for(i=-2;i<=2;i=i+1)for(j=-2;j<=2;j=j+1)begin
       exa=exa+coef_a(bxp[12]+i,byp[12]+j,bfp[12]);exb=exb+coef_b(bxp[12]+i,byp[12]+j,bfp[12]);
     end
     exa=(exa+12)/25;exb=(exb+12)/25;
     for(i=0;i<2;i=i+1)if(be[i]!==0 || ba[i]!==exa[11:0] || bb[i]!==exb[15:0] ||
       bc[i]!==pix(bxp[12],byp[12],bfp[12]) || bx[i]!==bxp[12] || by[i]!==byp[12] || bf[i]!==bfp[12])
       $fatal(1,"box mismatch variant %0d cycle %0d xy=%0d,%0d actual center=%0d expected=%0d",i,cycle,bxp[12],byp[12],bc[i],pix(bxp[12],byp[12],bfp[12]));
     bcount=bcount+1;
   end
 end
 task idle(input integer n);integer q;begin
   for(q=0;q<n;q=q+1)begin @(negedge clk);iv=0;cv=0;sof=0;csof=0;end
 end endtask
 task frame(input integer ff,gaps,cut);integer xx,yy,n,aa,bcnt;begin
   aa=acount;bcnt=bcount;n=0;fid=ff;
   for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
     if(gaps && ((xx+yy*7)%13==0))idle(3);
     if(gaps && xx==0)idle(19);
     @(negedge clk);iv=1;x=xx;y=yy;sof=(xx==0 && yy==0);pixel=pix(xx,yy,ff);
     cv=(xx<W-4 && yy<H-4);cx=xx+2;cy=yy+2;csof=sof;
     a=coef_a(xx+2,yy+2,ff);b=coef_b(xx+2,yy+2,ff);center=pix(xx+2,yy+2,ff);
     n=n+1;
     if(cut && n==cut)begin
       @(negedge clk);iv=0;cv=0;abort=1;idle(3);abort=0;
       return;
     end
   end
   idle(30);
   if(acount-aa!=(W-4)*(H-4) || bcount-bcnt!=(W-8)*(H-8))$fatal(1,"count mismatch");
 end endtask
 initial begin
   idle(3);rst=0;
   frame(1,0,0);frame(2,1,0);
   frame(3,1,6*W+9);frame(4,0,0);
   @(negedge clk);rst=1;idle(3);rst=0;frame(5,1,0);
   $display("PASS tb_resource_exchange W=%0d H=%0d moments=%0d box=%0d latency=9/12 II=1 bubbles linegaps abort reset",W,H,acount,bcount);
   $finish;
 end
 initial begin #200000000;$fatal(1,"watchdog");end
endmodule
module tb_resource_exchange17;tb_resource_exchange #(17,19) t();endmodule
module tb_resource_exchange_vga;tb_resource_exchange #(640,480) t();endmodule
