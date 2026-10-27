`timescale 1ns/1ps
// Expected words are derived from a fixed external rectangle, never DUT wires.
module tb_nt35510_window;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,start_valid=0,pixel_valid=0;
  reg [15:0] xs=700,xe=702,ys=260,ye=261,pixel=0;
  wire start_ready,pixel_ready,word_valid,word_rs,word_ready,word_done,busy,done,error;
  wire [15:0] word;wire [31:0] accepted;
  wire [7:0] data;wire cs_n,rs,wr_n,rd_n;
  nt35510_window_writer dut(.clk(clk),.rst(rst),.start_valid(start_valid),.start_ready(start_ready),
    .x_start(xs),.x_end(xe),.y_start(ys),.y_end(ye),.pixel_valid(pixel_valid),
    .pixel_rgb565(pixel),.pixel_ready(pixel_ready),.word_valid(word_valid),.word(word),
    .word_rs(word_rs),.word_ready(word_ready),.word_done(word_done),.busy(busy),
    .done(done),.error(error),.pixels_accepted(accepted));
  nt35510_bus8 bus(.clk(clk),.rst(rst),.in_valid(word_valid),.in_word(word),.in_rs(word_rs),
    .in_ready(word_ready),.lcd_data(data),.lcd_cs_n(cs_n),.lcd_rs(rs),.lcd_wr_n(wr_n),
    .lcd_rd_n(rd_n),.word_done(word_done));
  integer physical_words=0,physical_bytes=0,byte_phase=0,completed=0,errors=0,i;
  reg [7:0] upper;reg saved_rs;
  reg checking=1;
  function automatic [16:0] expected(input integer index);
    begin
      case(index)
        0:expected=17'h02a00;1:expected=17'h10002;
        2:expected=17'h02a01;3:expected=17'h100bc;
        4:expected=17'h02a02;5:expected=17'h10002;
        6:expected=17'h02a03;7:expected=17'h100be;
        8:expected=17'h02b00;9:expected=17'h10001;
        10:expected=17'h02b01;11:expected=17'h10004;
        12:expected=17'h02b02;13:expected=17'h10001;
        14:expected=17'h02b03;15:expected=17'h10005;
        16:expected=17'h02c00;
        17:expected=17'h1f800;18:expected=17'h107e0;19:expected=17'h1001f;
        20:expected=17'h1ffff;21:expected=17'h10000;22:expected=17'h18410;
        default:expected=17'hxxxxx;
      endcase
    end
  endfunction
  always @(posedge rst)begin byte_phase=0;physical_words=0;end
  always @(posedge wr_n)if(!rst && !cs_n)begin
    if(rd_n!==1)$fatal(1,"read and write asserted together");
    physical_bytes=physical_bytes+1;
    if(byte_phase==0)begin upper=data;saved_rs=rs;byte_phase=1;end
    else begin
      if(rs!==saved_rs)$fatal(1,"RS changed between bytes");
      if(checking && (physical_words>=23 || {rs,upper,data}!==expected(physical_words)))
        $fatal(1,"window physical word %0d got=%h expected=%h",physical_words,{rs,upper,data},expected(physical_words));
      physical_words=physical_words+1;byte_phase=0;
    end
  end
  always @(posedge clk)begin
    #1;
    if(!rst && done)begin
      if(physical_words!=23 || byte_phase || accepted!=6 || busy)
        $fatal(1,"rectangle done before all six physical pixels completed");
      completed=completed+1;
    end
    if(!rst && error)errors=errors+1;
  end
  task start_rectangle;
    begin
      @(negedge clk);start_valid=1;
      @(posedge clk);if(!start_ready)$fatal(1,"unexpected busy writer");
      @(negedge clk);start_valid=0;
    end
  endtask
  task send_pixels;
    integer n;
    begin
      for(n=17;n<23;n=n+1)begin
        repeat((n%3)+1)@(negedge clk);
        pixel=expected(n);pixel_valid=1;
        @(posedge clk);while(!pixel_ready)@(posedge clk);
        @(negedge clk);pixel_valid=0;pixel=~pixel;
      end
    end
  endtask
  initial begin
    repeat(3)@(negedge clk);rst=0;
    // Reversed and out-of-range windows must produce no bus traffic.
    xs=703;xe=702;start_rectangle();repeat(10)@(negedge clk);
    xs=700;xe=800;start_rectangle();repeat(10)@(negedge clk);
    ys=480;ye=480;xe=702;start_rectangle();repeat(10)@(negedge clk);
    if(errors!=3 || physical_words!=0 || busy)$fatal(1,"invalid rectangles emitted bus traffic");
    xs=700;xe=702;ys=260;ye=261;start_rectangle();
    // Changing external geometry while busy must not change the latched window.
    xs=0;xe=0;ys=0;ye=0;
    send_pixels();wait(done);repeat(5)@(negedge clk);
    if(completed!=1)$fatal(1,"missing completion");
    // Cancel a selected physical word with a reset shorter than one clock.
    checking=0;xs=700;xe=702;ys=260;ye=261;start_rectangle();
    wait(!wr_n && !cs_n);#1;rst=1;#1;
    if(!cs_n || !wr_n || word_valid || pixel_ready || start_ready || done)
      $fatal(1,"asynchronous cancellation did not make outputs safe");
    #1;rst=0;checking=1;
    repeat(10)@(negedge clk);
    if(physical_words || done || busy)$fatal(1,"cancelled rectangle resumed");
    start_rectangle();send_pixels();wait(done);repeat(5)@(negedge clk);
    if(completed!=2 || errors!=3)$fatal(1,"wrong completed/error counts");
    $display("PASS tb_nt35510_window rectangles=%0d invalid=%0d cancelled=1 high_coordinates=700..702/260..261 physical_bytes=%0d",completed,errors,physical_bytes);
    $finish;
  end
  initial begin #1000000;$fatal(1,"window watchdog expired");end
endmodule
