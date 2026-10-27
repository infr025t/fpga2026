`timescale 1ns/1ps
module tb_arithmetic;
  reg clk=0; always #5 clk=~clk;
  reg rst=1, abort=0, dv=0, rv=0;
  reg [20:0] n=0; reg [23:0] v=0, den=0;
  wire do_valid, ro_valid, de, re;
  wire [15:0] q; wire [11:0] a;
  div25_pipe d(clk,rst,abort,dv,n,do_valid,q,de);
  ratio_q12_pipe r(clk,rst,abort,rv,v,den,ro_valid,a,re);
  // Smaller legal parameter configuration runs alongside the default divider.
  wire sdv,sde; wire [11:0] sq;
  div25_pipe #(.IN_W(17),.OUT_W(12)) sd(clk,rst,abort,dv,n[16:0],sdv,sq,sde);
  wire p0v,p1v,p3v; wire [20:0] p0,p1,p3;
  token_pipe #(.WIDTH(21),.LATENCY(0)) pzero(clk,rst,abort,dv,n,p0v,p0);
  token_pipe #(.WIDTH(21),.LATENCY(1)) pone(clk,rst,abort,dv,n,p1v,p1);
  token_pipe #(.WIDTH(21),.LATENCY(3)) pthree(clk,rst,abort,dv,n,p3v,p3);
  reg [15:0] eq[0:4]; reg ev[0:4], ee[0:4];
  reg [11:0] ea[0:13]; reg av[0:13], ae[0:13];
  reg [20:0] pdata[0:3]; reg pv[0:3];
  reg [11:0] seq[0:4]; reg see[0:4];
  integer wantq=0,wantd=0,wanta=0,wantr=0;
  integer i,checks_d=0,checks_r=0,cycles=0,streak=0,maxstreak=0;
  integer fd,fr,rc,ni,qi,di,vi,deni,ai,ri;
  integer sent_d=0,sent_r=0;
  reg [31:0] random_state=32'h23102026;
  reg done_d=0,done_r=0;
  string base;
  always @(posedge clk) begin
    cycles=cycles+1;
    if(rst || abort) begin
      for(i=0;i<=4;i=i+1) begin ev[i]=0; ee[i]=0; end
      for(i=0;i<=13;i=i+1) begin av[i]=0; ae[i]=0; end
      for(i=0;i<=3;i=i+1) pv[i]=0;
    end else begin
      for(i=4;i>0;i=i-1) begin ev[i]=ev[i-1]; eq[i]=eq[i-1]; ee[i]=ee[i-1]; seq[i]=seq[i-1];see[i]=see[i-1];end
      ev[0]=dv;eq[0]=wantq;ee[0]=wantd;
      seq[0]=(n[16:0]/25 <=4095) ? n[16:0]/25 : 0;
      see[0]=(n[16:0]/25 >4095);
      for(i=13;i>0;i=i-1) begin av[i]=av[i-1];ea[i]=ea[i-1];ae[i]=ae[i-1];end
      av[0]=rv;ea[0]=wanta;ae[0]=wantr;
      for(i=3;i>0;i=i-1) begin pv[i]=pv[i-1];pdata[i]=pdata[i-1];end
      pv[0]=dv;pdata[0]=n;
    end
    #1;
    if(do_valid !== ev[4] || ro_valid !== av[13]) $fatal(1,"valid latency cycle %0d",cycles);
    if(de !== (ev[4] && ee[4]) || re !== (av[13] && ae[13])) $fatal(1,"error validity cycle %0d",cycles);
    if(ev[4]) begin
      if(q !== eq[4]) $fatal(1,"div mismatch got %0d expected %0d",q,eq[4]);
      if(sdv !== 1 || sq !== seq[4] || sde !== see[4]) $fatal(1,"small divider mismatch");
      checks_d=checks_d+1;streak=streak+1;if(streak>maxstreak)maxstreak=streak;
    end else begin streak=0;if(sdv !== 0 || sde !== 0)$fatal(1,"small spurious valid/error");end
    if(av[13]) begin if(a !== ea[13])$fatal(1,"ratio mismatch got %0d want %0d",a,ea[13]); checks_r=checks_r+1;end
    if(p0v !== (dv && !rst && !abort) || (p0v && p0 !== n))$fatal(1,"L0 pipe");
    if(p1v !== pv[1] || (p1v && p1 !== pdata[1]))$fatal(1,"L1 pipe");
    if(p3v !== pv[3] || (p3v && p3 !== pdata[3]))$fatal(1,"L3 pipe");
  end
  initial begin
    if(!$value$plusargs("VECTORS=%s",base))$fatal(1,"no vectors");
    repeat(3)@(negedge clk);rst=0;
    // Flush occupied pipelines, with valid still asserted on flush edges.
    repeat(20)begin @(negedge clk);dv=1;n=26;wantq=1;rv=1;v=1;den=8192;wanta=1;end
    @(negedge clk);abort=1;
    @(negedge clk);abort=0;dv=0;rv=0;
    repeat(16)@(negedge clk);
    repeat(20)begin @(negedge clk);dv=1;rv=1;end
    @(negedge clk);rst=1;
    @(negedge clk);rst=0;dv=0;rv=0;
    repeat(16)@(negedge clk);
    checks_d=0;checks_r=0;maxstreak=0;
    fd=$fopen({base,"/div.txt"},"r");fr=$fopen({base,"/ratio.txt"},"r");
    if(!fd || !fr)$fatal(1,"vector open failed");
    while(!done_d || !done_r) begin
      @(negedge clk);dv=0;rv=0;n='x;v='x;den='x;
      random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
      // Initial full-rate burst; then repeatable pseudorandom bubbles/line gaps.
      if(cycles<4096 || (random_state[3:0]!=0 && cycles%2053<2048))begin
        if(!done_d)begin
          rc=$fscanf(fd,"%d %d %d\n",ni,qi,di);
          if(rc==3)begin dv=1;n=ni;wantq=qi;wantd=di;sent_d=sent_d+1;end else done_d=1;
        end
        if(!done_r && (cycles<4096 || random_state[7:4]!=0))begin
          rc=$fscanf(fr,"%d %d %d %d\n",vi,deni,ai,ri);
          if(rc==4)begin rv=1;v=vi;den=deni;wanta=ai;wantr=ri;sent_r=sent_r+1;end else done_r=1;
        end
      end
    end
    @(negedge clk);dv=0;rv=0;
    repeat(20)@(negedge clk);
    if(sent_d==0 || sent_r<20000 || checks_d!=sent_d || checks_r!=sent_r)$fatal(1,"lost vectors");
    if(sent_d>1000 && maxstreak<1000)$fatal(1,"missing II1 burst");
    $display("PASS tb_arithmetic div_checks=%0d ratio_checks=%0d max_II1_streak=%0d latencies=4,13 token=0,1,3",checks_d,checks_r,maxstreak);
    $finish;
  end
endmodule
