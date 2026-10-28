`timescale 1ns/1ps
// Panel-side GRAM model: only physical rising WR strobes advance this model.
module tb_nt35510_display #(parameter integer FULL=0);
  localparam integer PW=FULL?800:9,PH=FULL?480:9,CW=FULL?632:1,CH=FULL?472:1;
  localparam integer LEFT=(PW-CW)/2,TOP=(PH-CH)/2;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,enable=0;reg [1:0] pattern_select=0;
  wire [7:0] data;wire cs_n,rs,wr_n,rd_n,reset_n,bl,initialized,background_done,frame_done,busy,error;
  wire [31:0] frames;
  nt35510_test_display #(.PANEL_W(PW),.PANEL_H(PH),.CORE_W(CW),.CORE_H(CH),.CLK_HZ(1000)) dut(
    .clk(clk),.rst(rst),.enable(enable),.pattern_select(pattern_select),
    .lcd_data(data),.lcd_cs_n(cs_n),.lcd_rs(rs),.lcd_wr_n(wr_n),.lcd_rd_n(rd_n),
    .lcd_reset_n(reset_n),.lcd_bl(bl),.initialized(initialized),.background_done(background_done),
    .frame_done(frame_done),.rendered_frames(frames),.busy(busy),.error(error));
  reg [16:0] init_expected[0:731];reg [15:0] gram[0:PW*PH-1];
  integer init_words=0,byte_phase=0,setup_index=0,transaction=0,pixels=0;
  integer physical_frames=0,total_frames=0,total_clear=0,total_bytes=0,mode_to_expect=0;
  integer model_frame_index=0,frame_done_count=0,cycle=0;
  integer window_x0,window_x1,window_y0,window_y1;
  integer expected_x0,expected_x1,expected_y0,expected_y1;
  integer wanted_pixels,wanted_gray,local_x,local_y,address,model_x,model_y;
  reg [7:0] upper;reg saved_rs;
  reg [15:0] wanted_value;
  string vector_dir,output_dir;

  function automatic [16:0] window_word(input integer index,input integer x0,x1,y0,y1);
    begin
      case(index)
        0:window_word=17'h02a00;1:window_word=17'h10000|((x0>>8)&255);
        2:window_word=17'h02a01;3:window_word=17'h10000|(x0&255);
        4:window_word=17'h02a02;5:window_word=17'h10000|((x1>>8)&255);
        6:window_word=17'h02a03;7:window_word=17'h10000|(x1&255);
        8:window_word=17'h02b00;9:window_word=17'h10000|((y0>>8)&255);
        10:window_word=17'h02b01;11:window_word=17'h10000|(y0&255);
        12:window_word=17'h02b02;13:window_word=17'h10000|((y1>>8)&255);
        14:window_word=17'h02b03;15:window_word=17'h10000|(y1&255);
        default:window_word=17'h02c00;
      endcase
    end
  endfunction
  function automatic [15:0] gray565(input integer value);
    reg [7:0] g;
    begin g=value;gray565={g[7:3],g[7:2],g[7:3]};end
  endfunction

  task consume_word(input [16:0] incoming);
    begin
      if(init_words<732)begin
        if(incoming!==init_expected[init_words])
          $fatal(1,"display initialization physical word %0d got=%h expected=%h",init_words,incoming,init_expected[init_words]);
        init_words=init_words+1;
      end else if(setup_index<17)begin
        if(transaction==0)begin expected_x0=0;expected_x1=PW-1;expected_y0=0;expected_y1=PH-1;end
        else begin expected_x0=LEFT;expected_x1=LEFT+CW-1;expected_y0=TOP;expected_y1=TOP+CH-1;end
        if(incoming!==window_word(setup_index,expected_x0,expected_x1,expected_y0,expected_y1))
          $fatal(1,"display rectangle %0d setup %0d got=%h",transaction,setup_index,incoming);
        // Decode address bytes separately to update the panel GRAM cursor.
        case(setup_index)
          1:window_x0=(incoming&255)<<8;3:window_x0=window_x0|(incoming&255);
          5:window_x1=(incoming&255)<<8;7:window_x1=window_x1|(incoming&255);
          9:window_y0=(incoming&255)<<8;11:window_y0=window_y0|(incoming&255);
          13:window_y1=(incoming&255)<<8;15:window_y1=window_y1|(incoming&255);
          16:begin model_x=window_x0;model_y=window_y0;pixels=0;end
        endcase
        setup_index=setup_index+1;
      end else begin
        if(incoming[16]!==1)$fatal(1,"pixel sent as command");
        if(transaction==0)begin wanted_pixels=PW*PH;wanted_value=0;end
        else begin
          wanted_pixels=CW*CH;local_x=pixels%CW;local_y=pixels/CW;
          case(mode_to_expect)
            0:wanted_gray=(local_x+4+local_y+4+model_frame_index)%256;
            1:wanted_gray=((((local_x+4)/16)+((local_y+4)/16))%2==0)?32:224;
            2:wanted_gray=(2*(local_x+4)<CW+8)?32:224;
            default:wanted_gray=128;
          endcase
          wanted_value=gray565(wanted_gray);
        end
        if(incoming[15:0]!==wanted_value)
          $fatal(1,"display rectangle=%0d pixel=%0d mode=%0d got=%h want=%h",transaction,pixels,mode_to_expect,incoming[15:0],wanted_value);
        if(model_x<window_x0 || model_x>window_x1 || model_y<window_y0 || model_y>window_y1)
          $fatal(1,"GRAM cursor escaped window");
        address=model_y*PW+model_x;gram[address]=incoming[15:0];pixels=pixels+1;
        if(model_x==window_x1)begin model_x=window_x0;model_y=model_y+1;end
        else model_x=model_x+1;
        if(pixels==wanted_pixels)begin
          if(model_y!=window_y1+1 || model_x!=window_x0)$fatal(1,"wrong rectangular pixel count");
          if(transaction==0)total_clear=total_clear+1;
          else begin physical_frames=physical_frames+1;total_frames=total_frames+1;model_frame_index=model_frame_index+1;end
          transaction=transaction+1;setup_index=0;
        end
      end
    end
  endtask

  always @(posedge rst)begin
    init_words=0;byte_phase=0;setup_index=0;transaction=0;pixels=0;physical_frames=0;
    model_frame_index=0;frame_done_count=0;
  end
  always @(posedge wr_n)if(!rst && !cs_n)begin
    if(!reset_n || rd_n!==1)$fatal(1,"bus write while panel reset/read active");
    total_bytes=total_bytes+1;
    if(byte_phase==0)begin upper=data;saved_rs=rs;byte_phase=1;end
    else begin
      if(saved_rs!==rs)$fatal(1,"RS changed between bytes");
      consume_word({rs,upper,data});byte_phase=0;
    end
  end
  always @(posedge clk)begin
    cycle=cycle+1;#1;
    if(!rst)begin
      if(error)$fatal(1,"unexpected display error");
      if(initialized && init_words!=732)$fatal(1,"init_done before physical initialization finished");
      if(background_done && transaction<1)$fatal(1,"background_done before full black clear");
      if(bl && (!initialized || !background_done || transaction<1))$fatal(1,"backlight lit before initialization and full clear");
      if(frame_done)begin
        frame_done_count=frame_done_count+1;
        if(frame_done_count!=physical_frames || frames!=physical_frames || byte_phase || !cs_n)
          $fatal(1,"frame completion does not match fully written GRAM");
      end
    end
    if(cycle>12000000)$fatal(1,"display watchdog expired");
  end

  task check_margins;
    integer x,y;
    begin
      for(y=0;y<PH;y=y+1)for(x=0;x<PW;x=x+1)
        if((x<LEFT || x>=LEFT+CW || y<TOP || y>=TOP+CH) && gram[y*PW+x]!==0)
          $fatal(1,"static black margin changed at %0d,%0d",x,y);
    end
  endtask
  task render(input integer mode);
    integer goal,saved_bytes;
    begin
      goal=physical_frames+1;mode_to_expect=mode;
      @(negedge clk);pattern_select=mode;enable=1;
      wait(setup_index==17 && pixels==5);
      // Mid-frame changes must not affect the frame already being rendered.
      @(negedge clk);enable=0;pattern_select=(mode+1)%4;
      wait(frame_done_count==goal);repeat(4)@(negedge clk);
      saved_bytes=total_bytes;repeat(40)@(negedge clk);
      if(total_bytes!=saved_bytes || frames!=goal || busy)$fatal(1,"pause started an extra transaction");
      check_margins();
    end
  endtask
  task export_ppm;
    integer fd,n,r,g,b;
    reg [15:0] value;
    begin
      if(output_dir!="")begin
        fd=$fopen({output_dir,"/panel.ppm"},"wb");if(fd==0)$fatal(1,"cannot create panel preview");
        $fwrite(fd,"P6\n%0d %0d\n255\n",PW,PH);
        for(n=0;n<PW*PH;n=n+1)begin
          value=gram[n];r=((value>>11)&31)*255/31;g=((value>>5)&63)*255/63;b=(value&31)*255/31;
          $fwrite(fd,"%c%c%c",r,g,b);
        end
        $fclose(fd);
      end
    end
  endtask
  integer before_reset_frames;
  initial begin
    if(!$value$plusargs("VECTORS=%s",vector_dir))$fatal(1,"missing expected initialization source vectors");
    if(!$value$plusargs("OUTPUT=%s",output_dir))output_dir="";
    $readmemh({vector_dir,"/expected_init.hex"},init_expected);
    repeat(3)@(negedge clk);rst=0;
    wait(background_done);repeat(20)@(negedge clk);
    if(!bl || total_clear!=1 || physical_frames || busy)$fatal(1,"initial black clear/backlight/pause failed");
    // Keep enable asserted across successive physical frame boundaries.
    mode_to_expect=0;@(negedge clk);pattern_select=0;enable=1;
    wait(frame_done_count==4);
    @(negedge clk);enable=0;
    repeat(50)@(negedge clk);
    if(physical_frames!=4 || frames!=4 || transaction!=5 || setup_index!=0 || busy)
      $fatal(1,"continuous frames had extra/missing pixels or transaction");
    check_margins();
    export_ppm();
    $display("PASS tb_nt35510_display full=%0d panel=%0dx%0d active=%0dx%0d viewport=%0d..%0d/%0d..%0d clear=%0d physical_frames=%0d total_bytes=%0d cycles=%0d",FULL,PW,PH,CW,CH,LEFT,LEFT+CW-1,TOP,TOP+CH-1,total_clear,total_frames,total_bytes,cycle);
    $finish;
  end
endmodule

module tb_nt35510_display_full;
  tb_nt35510_display #(.FULL(1)) test();
endmodule

// Elaborate the actual pin-independent board wrapper, not a replacement top.
// This smoke check covers power-up safety and switch/button synchronization;
// the scaled-clock tests above exercise complete initialization and rendering.
module tb_nt35510_bringup;
  reg clk=0;always #5 clk=~clk;
  reg button=0;reg [15:0] switches=16'h8003;
  wire [7:0] data;wire cs_n,rs,wr_n,rd_n,reset_n,bl;wire [15:0] led;
  nt35510_bringup_top dut(.clk100(clk),.btnC(button),.sw(switches),
    .lcd_data(data),.lcd_cs_n(cs_n),.lcd_rs(rs),.lcd_wr_n(wr_n),.lcd_rd_n(rd_n),
    .lcd_reset_n(reset_n),.lcd_bl(bl),.led(led));
  task check_safe;
    begin
      if(cs_n!==1 || wr_n!==1 || rd_n!==1 || reset_n!==0 || bl!==0 || data!==0)
        $fatal(1,"board wrapper did not hold LCD safe during startup/reset");
      if((^led)===1'bx)$fatal(1,"unknown status LED at board wrapper");
    end
  endtask
  initial begin
    repeat(25)begin @(negedge clk);check_safe();end
    if(led[6]!==1 || led[0]!==0 || led[7]!==0)$fatal(1,"board switch/status mapping incorrect");
    button=1;repeat(5)begin @(negedge clk);check_safe();end
    button=0;switches=0;repeat(25)begin @(negedge clk);check_safe();end
    if(led[6]!==0)$fatal(1,"pause switch did not synchronize");
    $display("PASS tb_nt35510_bringup cycles=55 startup_pins=safe pause_switch=synchronized");
    $finish;
  end
endmodule
