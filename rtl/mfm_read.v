// MFM reader

module mfm_read
  (
  input reset_l,

  // 24 MHz clock

  input clk,

  // Read pulses in

  input read_pulse_l,

  // Decoded bytes out

  output reg [7:0] data_out,	// Data byte
  output reg mark,		// Set if byte is an address mark
  output reg valid,		// Set if valid
  output reg crc_zero		// Set if CRC is 0 (meaning no errors) after this byte
  );

// Clock/Data separator

parameter PERIOD = (24 * 256);
// No. clocks per period * 256 (one period is 1/2 bit time: 1us for MFM)

parameter HALF = (PERIOD / 2);

reg [12:0] count;	// Bit window timer

reg capture;		// Set if bit was found in this window

reg [2:0] leading;	// Synchronizer and leading edge detector

reg sep_clock;
reg sep_data;

reg [12:0] adjust; // Amount to add to clock

always @(posedge clk or negedge reset_l)
  if (!reset_l)
    begin
      leading <= 3'b111;
      capture <= 0;
      count <= 0;
      sep_clock <= 0;
      sep_data <= 0;
    end
  else
    begin
      sep_clock <= 0;

      // Feed leading edge detector
      leading <= { read_pulse_l, leading[2:1] };

      // Normal counter increment
      adjust = 256;

      // We detect an edge
      if (!leading[1] && leading[0])
        begin
          // Note that edge was detected
          capture <= 1;

          // Bump counter: it should be at HALF
          if (count > HALF)
            // We're too fast: retard
            adjust = 256 - ((count-HALF)>>1);
          else if (count < HALF)
            // We're too slow: advance
            adjust = 256 + ((count-HALF)>>1);
        end

      // Advance clock
      if (count + adjust >= PERIOD)
        begin
          count <= count + adjust - PERIOD;
          capture <= 0;
          sep_clock <= 1;
          sep_data <= capture;
        end
      else
        count <= count + adjust;

    end

// Address mark detector, byte aligner

reg [15:0] shift_reg;	// Shift register
reg [3:0] shift_count;

// Data bits

wire [7:0] data = { shift_reg[14], shift_reg[12], shift_reg[10], shift_reg[8],
                    shift_reg[6], shift_reg[4], shift_reg[2], shift_reg[0] };

// Clock bits

wire [7:0] clock = { shift_reg[15], shift_reg[13], shift_reg[11], shift_reg[9],
                     shift_reg[7], shift_reg[5], shift_reg[3], shift_reg[1] };

reg [7:0] aligned_byte;
reg aligned_valid;
reg aligned_mark;

always @(posedge clk or negedge reset_l)
  if(!reset_l)
    begin
      shift_reg <= 0;
      shift_count <= 0;
      aligned_mark <= 0;
      aligned_byte <= 0;
      aligned_valid <= 0;
    end
  else
    begin
      aligned_valid <= 0;
      if(sep_clock)
        begin
          shift_reg <= { shift_reg[14:0], sep_data };

          if(shift_count)
            shift_count <= shift_count - 1;

          if(clock==8'h0A && data==8'hA1 || !shift_count)
            begin
              shift_count <= 15;
              aligned_byte <= data;
              aligned_valid <= 1;
              if(clock==8'h0A && data==8'hA1)
                aligned_mark <= 1;
              else
                aligned_mark <= 0;
            end
        end
    end

// CRC checker

function [15:0] crc;
input [15:0] accu;
input [7:0] byte;
  begin
    crc[0] = accu[4'h8]^accu[4'hC]^byte[4]^byte[0];
    crc[1] = accu[4'h9]^accu[4'hD]^byte[5]^byte[1];
    crc[2] = accu[4'hA]^accu[4'hE]^byte[6]^byte[2];
    crc[3] = accu[4'hB]^accu[4'hF]^byte[7]^byte[3];
    crc[4] = accu[4'hC]^byte[4];
    crc[5] = accu[4'hD]^byte[5]^accu[4'h8]^accu[4'hC]^byte[4]^byte[0];
    crc[6] = accu[4'hE]^byte[6]^accu[4'h9]^accu[4'hD]^byte[5]^byte[1];
    crc[7] = accu[4'hF]^byte[7]^accu[4'hA]^accu[4'hE]^byte[6]^byte[2];
    crc[8] = accu[4'h0]^accu[4'hB]^accu[4'hF]^byte[7]^byte[3];
    crc[9] = accu[4'h1]^accu[4'hC]^byte[4];
    crc[10] = accu[4'h2]^accu[4'hD]^byte[5];
    crc[11] = accu[4'h3]^accu[4'hE]^byte[6];
    crc[12] = accu[4'h4]^accu[4'hF]^byte[7]^accu[4'h8]^accu[4'hC]^byte[4]^byte[0];
    crc[13] = accu[4'h5]^accu[4'h9]^accu[4'hD]^byte[5]^byte[1];
    crc[14] = accu[4'h6]^accu[4'hA]^accu[4'hE]^byte[6]^byte[2];
    crc[15] = accu[4'h7]^accu[4'hB]^accu[4'hF]^byte[7]^byte[3];
  end
endfunction

reg [15:0] fcs;
reg [2:0] count;

always @(posedge clk or negedge reset_l)
  if(!reset_l)
    begin
      fcs <= 0;
      count <= 0;
      data_out <= 0;
      mark <= 0;
      valid <= 0;
      crc_zero <= 0;
    end
  else
    begin
      if(aligned_valid)
        begin
          data_out <= aligned_data;
          valid <= 1;
          mark <= aligned_mark;

          fcs <= compute_fcs(fcs, aligned_byte);
          crc_zero <= (compute_fcs(fcs, aligned_byte)==16'h0000);

          // Ignore address marks after the first one
          if(count)
            count <= count - 1;
          else if(aligned_mark)
            begin
              // Start of packet: initial crc
              fcs <= compute_fcs(16'hFFFF, aligned_byte);
              count <= 4;
            end
        end
      else
        valid <= 0;
    end

endmodule
