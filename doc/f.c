/* Floppy drive data separator and CRC checker simulation in C.

   This C program performs clock/data separation, address mark
   recognition and CRC checking of logic analyzer trace of floppy
   drive read data line.

   Compile: cc -o f f.c
   Run: ./f <example_data.txt >output.txt
*/

/* x^16 + x^12 + x^5 + 1 CRC */
/* Append remainder (contents of fcs) to message: MSB of remainder goes first. */
/* Next time through, remainder will be zero. */
/* fcs is typically initialized to 0xFFFF */

/* Update FCS after one new byte (note that the MSB is taken first even though the LSB is transmitted first) */
unsigned short serial_crc(unsigned short fcs,unsigned char c)
  {
  int i;
  for(i=0;i!=8;++i)
    {
    fcs = ((fcs&0x8000)>>15)^(c>>7) ? (fcs<<1)^0x1021 : (fcs<<1);

    c = (c<<1);
    }
  return fcs;
  }

/* No. samples per bit cell (two bit cells store one data bit in MFM)
 * times 256 */

#define SAMPLE_RATE 5 /* MHz */

#define TIME (SAMPLE_RATE*256)
/* Timer */
int count;

/* Shift register for data and clock bits */
int shift_reg[16];
int shift_count;

int capture;
int lead;

int found=0;

/* Call this for each time step: rd is read data line */
int stepno;

unsigned short fcs;

step(rd)
  {
  ++stepno;

  /* printf("%d\n",rd); */

  /* Leading edge detector */
  if(rd==0 && lead==1)
    {
    /* Move counter toward TIME/2 */

    /* Adjust count */
    if(count>TIME/2)
      /* We're early: retard */
      {
      /* printf("diff=%d\n",count-TIME/2); */
      count -= (count-TIME/2)/2;
      }
    else if(count<TIME/2)
      {
      /* printf("diff=%d\n",TIME/2-count); */
      /* We're late: advance */
      count += (TIME/2-count)/2;
      }
    else
      {
      /* printf("no diff\n"); */
      }

    capture=1;
    }
  lead=rd;

  /* Timer */
  count = count + 256;
  if(count>=TIME)
    {
    int x;
    int clock;
    int data;
    count -= TIME;

    for(x=15;x!=0;--x)
      shift_reg[x] = shift_reg[x-1];
    shift_reg[0] = capture;

    capture = 0;

    shift_count = shift_count + 1;

    clock = (shift_reg[15]<<7) | (shift_reg[13]<<6) | (shift_reg[11]<<5) | (shift_reg[9]<<4) |
            (shift_reg[7]<<3) | (shift_reg[5]<<2) | (shift_reg[3]<<1) | (shift_reg[1]);

    data = (shift_reg[14]<<7) | (shift_reg[12]<<6) | (shift_reg[10]<<5) | (shift_reg[8]<<4) |
           (shift_reg[6]<<3) | (shift_reg[4]<<2) | (shift_reg[2]<<1) | (shift_reg[0]);

    /* Check for address mark */
    if(clock==0x0A && data==0xA1)
      {
      printf("Address mark A1 found\n");
      shift_count=16;
      if(!found)
        {
        /* Initialize CRC */
        /* Ignore next few bytes to prevent successive address marks
           from restarting us again */
        found=4;
        fcs=0xFFFF;
        }
      }

    if(shift_count==16)
      {
      if(found)
        --found;
      fcs = serial_crc(fcs,data);
      printf("clock=%2.2x data=%2.2x crc=%x\n",clock,data,fcs);

      shift_count=0;
      }
    }
  }

main()
  {
  char buf[1024];
  while(gets(buf))
    step(buf[0]=='1');
  }
