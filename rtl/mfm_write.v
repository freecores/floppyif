// Encode data as MFM and serialize it

module mfm_write
  (
  input reset_l,
  input clk,

  // Read data from encode FIFO

  input start_writing,			// Flip to start writing

  input [7:0] encode_fifo_rd_data,
  input encode_fifo_rd_mark,		// Set for address mark
  input encode_fifo_done,		// Set along with last word to complete write
  input encode_fifo_ne,			// Not empty
  output reg encode_fifo_re,		// Read enable

  // Encoded data out

  output reg write_gate_l,		// Held low during writing
  output reg serial_out_l		// Pulses low for each flux reversal
  );

parameter BIT_RATE_DIVISOR = 24;	// No. clks per bit cell (two bit cells for transmitted bit)
parameter PULSE_WIDTH = 5;		// Pulse width

reg [6:0] counter;			// Bit cell counter
reg [7:0] shift_reg;			// Transmit shift register
reg [2:0] bit_counter;			// Bit counter
reg prev_bit;				// Value of previously sent bit
reg clk_data;				// Set if next bit clock, clear if next is data

reg [3:0] pulse_counter;

always @(posedge clk or negedge reset_l)
  if(!reset_l)
    begin
      counter <= 0;
      pulse_counter <= 0;
      write_gate_l <= 1;
      serial_out_l <= 1;
      encode_fifo_re <= 0;
    end
  else
    begin
      encode_fifo_re <= 0;

      if (pulse_counter)
        pulse_counter <= pulse_counter - 1;
      else
        serial_out_l <= 1;

      if (counter)
        counter <= counter - 1;
      else
        begin
          counter <= BIT_RATE_DIVISOR - 1;
          if (clk_data)
            begin
              // Send clock
              clk_data <= 0;
              if (!shift_reg[0] && !prev_bit)
                begin
                  serial_out_l <= 0;
                  pulse_counter <= PULSE_WIDTH;
                end
            end
          else
            begin
              // Send data
              clk_data <= 1;
              if (shift_reg[0])
                begin
                  serial_out_l <= 0;
                  pulse_counter <= PULSE_WIDTH;
                end
              prev_bit <= shift_reg[0];
              if (bit_counter)
                bit_counter <= bit_counter - 1;
              else
                begin
                  // Get next byte from FIFO
                  shift_reg <= encode_fifo_rd_data;
                  encode_fifo_re <= 1;
                  bit_counter <= 7;
                end
            end
        end
    end

endmodule
